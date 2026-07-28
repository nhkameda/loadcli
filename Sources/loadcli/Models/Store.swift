import Foundation
import Combine

/// Owns the project index, the group styles and the settings.
///
/// The source of truth for projects is no longer a JSON file: it is the set of
/// `LOADCLI.md` documents found under the configured root folders. This class
/// keeps three things in sync with that idea:
///
/// * `index.json` — a *cache* of the last scan, so the window opens instantly
///   and the (slower) walk happens in the background;
/// * `folders.json` — only the style of each group (icon/colour/order), keyed by
///   the group name that lives inside the documents;
/// * `local.json` — the per-machine bits that must never travel: chosen monitor
///   and the "recentes" history.
@MainActor
final class Store: ObservableObject {
    /// Cards currently shown, sorted by name.
    @Published private(set) var projects: [Project] = []
    /// Group styles the user customised (may include groups with no cards yet).
    @Published private(set) var folderStyles: [ProjectFolder] = []
    @Published var settings = AppSettings()

    /// True while a scan is running (the UI shows a discreet "Atualizando…").
    @Published private(set) var isScanning = false
    /// Roots that could not be read on the last scan — their cards are kept.
    @Published private(set) var unavailableRoots: [String] = []
    /// Set once, right after the one-time upgrade from projects.json.
    @Published var migrationNotice: String?
    /// Last filesystem error worth showing the user.
    @Published var lastError: String?
    /// Machine-local preferences (monitor per project + recents).
    @Published private(set) var local = LocalPrefs()

    /// The indexed documents behind `projects`.
    private var entries: [ScannedProject] = []

    private let dir: URL
    private let indexURL: URL
    private let foldersURL: URL
    private let settingsURL: URL
    private let localURL: URL
    private let legacyProjectsURL: URL

    private struct IndexFile: Codable {
        var version: Int = 1
        var entries: [ScannedProject] = []
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("loadcli", isDirectory: true)
        indexURL = dir.appendingPathComponent("index.json")
        foldersURL = dir.appendingPathComponent("folders.json")
        settingsURL = dir.appendingPathComponent("settings.json")
        localURL = dir.appendingPathComponent("local.json")
        legacyProjectsURL = dir.appendingPathComponent("projects.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Load / save

    private func load() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: settingsURL),
           let s = try? dec.decode(AppSettings.self, from: data) {
            settings = s
        }
        if let data = try? Data(contentsOf: foldersURL),
           let f = try? dec.decode([ProjectFolder].self, from: data) {
            folderStyles = f.filter { !$0.id.isEmpty }
        }
        if let data = try? Data(contentsOf: indexURL),
           let file = try? dec.decode(IndexFile.self, from: data) {
            entries = file.entries
        }
        local = LocalPrefs.load(from: localURL)

        migrateIfNeeded()
        dedupeEntryIdentities()
        rebuild()
    }

    /// One-time upgrade: turn the old projects.json into LOADCLI.md documents
    /// and seed the scan roots from the folders that were registered.
    private func migrateIfNeeded() {
        guard LegacyMigration.isPending(projectsURL: legacyProjectsURL) else { return }
        let report = LegacyMigration.run(projectsURL: legacyProjectsURL,
                                         foldersURL: foldersURL,
                                         defaultProjectsFolder: settings.defaultProjectsFolder)

        // The old folders.json was keyed by UUID; whatever `load()` decoded from
        // it is meaningless now, so the converted list replaces it wholesale.
        folderStyles = report.folders
        if settings.projectRoots.isEmpty {
            settings.projectRoots = report.roots
        } else {
            settings.projectRoots = AppSettings.normalize(roots: settings.projectRoots + report.roots)
        }

        // Seed the cache so the very first window already shows every card,
        // before the background scan confirms them.
        entries = report.projects.compactMap { project -> ScannedProject? in
            guard !project.folderPath.isEmpty else { return nil }
            let docPath = ProjectDoc.path(inFolder: project.folderPath)
            let root = settings.normalizedRoots.first { project.folderPath.hasPrefix($0 + "/") } ?? ""
            return ScannedProject(project: project,
                                  documentPath: docPath,
                                  modified: Self.modificationDate(ofFile: docPath) ?? .distantPast,
                                  root: root)
        }

        saveSettings()
        saveFolders()
        saveIndex()
        if !report.isEmpty { migrationNotice = report.summary }
    }

    private func saveIndex() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(IndexFile(entries: entries)) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func saveFolders() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(folderStyles) {
            try? data.write(to: foldersURL, options: .atomic)
        }
    }

    func saveSettings() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(settings) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    private func saveLocal() { local.save(to: localURL) }

    /// Recompute the published card list from the indexed documents, injecting
    /// the machine-local monitor choice.
    private func rebuild() {
        projects = entries
            .map { entry -> Project in
                var p = entry.project
                p.monitorPreference = local.monitor(for: p.id)
                return p
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - Scanning

    /// Walk the configured roots and replace the card list with what is on disk.
    func refresh() async {
        guard !isScanning else { return }
        let roots = settings.normalizedRoots
        guard !roots.isEmpty else {
            entries = []
            unavailableRoots = []
            rebuild()
            saveIndex()
            return
        }

        isScanning = true
        defer { isScanning = false }

        let cache = Dictionary(entries.map { ($0.documentPath, $0) }, uniquingKeysWith: { first, _ in first })
        let outcome = await ProjectScanner.scan(roots: roots,
                                                maxDepth: settings.scanMaxDepth,
                                                cache: cache)

        var merged = outcome.found
        // A root we could not read keeps whatever it had cached, so a Drive that
        // hasn't finished syncing never wipes the list.
        let unreachable = Set(outcome.unavailableRoots)
        if !unreachable.isEmpty {
            let known = Set(merged.map(\.documentPath))
            merged.append(contentsOf: entries.filter {
                unreachable.contains($0.root) && !known.contains($0.documentPath)
            })
        }

        entries = merged
        unavailableRoots = outcome.unavailableRoots
        dedupeEntryIdentities()
        rebuild()
        saveIndex()
    }

    /// Copying a project folder in Finder copies its `LOADCLI.md` too — id and
    /// all. Give every clone after the first its own path-derived identity, so
    /// the two cards don't share recents/monitor state (and SwiftUI doesn't see
    /// duplicate ids in a `ForEach`).
    private func dedupeEntryIdentities() {
        var seen = Set<UUID>()
        for index in entries.indices {
            let id = entries[index].project.id
            if seen.insert(id).inserted { continue }
            var replacement = ProjectDoc.stableID(for: entries[index].project.folderPath)
            var attempts = 0
            while !seen.insert(replacement).inserted, attempts < 8 {
                replacement = UUID()
                attempts += 1
            }
            entries[index].project.id = replacement
        }
    }

    private static func modificationDate(ofFile path: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    // MARK: - Projects

    /// Cards belonging to `group` (nil = "sem pasta"), case-insensitive.
    func projects(in group: String?) -> [Project] {
        guard let group, !group.isEmpty else {
            return projects.filter { $0.groupName == nil }
        }
        let key = ProjectFolder.matchKey(for: group)
        return projects.filter { ProjectFolder.matchKey(for: $0.groupName ?? "") == key }
    }

    func project(withID id: UUID) -> Project? { projects.first { $0.id == id } }

    /// Create or update a project: writes its `LOADCLI.md`, refreshes the index
    /// and makes sure the folder is covered by a scan root. Returns an error
    /// message when the document could not be written.
    @discardableResult
    func upsert(_ project: Project) -> String? {
        var p = project
        p.folderPath = AppSettings.canonical(p.folderPath)
        guard !p.folderPath.isEmpty else {
            lastError = "Defina a pasta do projeto."
            return lastError
        }

        // The folder may have been changed in the editor — retire the old file.
        if let previous = entries.first(where: { $0.project.id == p.id }),
           previous.project.folderPath != p.folderPath {
            try? ProjectDoc.trashDocument(inFolder: previous.project.folderPath)
            entries.removeAll { $0.project.id == p.id }
        }

        let monitor = p.monitorPreference
        do {
            try ProjectDoc.write(p)
        } catch {
            lastError = "Não consegui gravar o LOADCLI.md em \(p.folderPath): \(error.localizedDescription)"
            return lastError
        }

        local.setMonitor(monitor, for: p.id)
        saveLocal()

        let docPath = ProjectDoc.path(inFolder: p.folderPath)
        let root = coveringRoot(for: p.folderPath) ?? adoptRoot(for: p.folderPath) ?? ""
        let entry = ScannedProject(project: p, documentPath: docPath,
                                   modified: Self.modificationDate(ofFile: docPath) ?? Date(),
                                   root: root)
        if let i = entries.firstIndex(where: { $0.project.id == p.id }) {
            entries[i] = entry
        } else if let i = entries.firstIndex(where: { $0.documentPath == docPath }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }

        ensureStyleExists(for: p.groupName)
        rebuild()
        saveIndex()
        return nil
    }

    /// Remove a card by moving its `LOADCLI.md` to the Trash. The project folder
    /// and its contents are never touched.
    func delete(_ project: Project) {
        do {
            try ProjectDoc.trashDocument(inFolder: project.folderPath)
        } catch {
            lastError = "Não consegui remover o LOADCLI.md: \(error.localizedDescription)"
        }
        entries.removeAll { $0.project.id == project.id }
        local.forget(project.id)
        saveLocal()
        rebuild()
        saveIndex()
    }

    /// Move a card to another group (nil = sem pasta), rewriting its document.
    func setGroup(_ group: String?, for project: Project) {
        var p = project
        p.group = group
        upsert(p)
    }

    /// A copy ready to be edited as a new project: fresh id, no folder yet.
    func duplicateDraft(of project: Project) -> Project {
        var copy = project
        copy.id = UUID()
        copy.name = project.name + " cópia"
        copy.folderPath = ""
        return copy
    }

    // MARK: - Groups

    /// Every group to render: those declared by cards plus any style-only group
    /// the user created, ordered by the stored index then alphabetically.
    var folders: [ProjectFolder] {
        var byKey: [String: ProjectFolder] = [:]
        for style in folderStyles {
            byKey[style.matchKey] = style
        }
        for project in projects {
            guard let name = project.groupName else { continue }
            let key = ProjectFolder.matchKey(for: name)
            if byKey[key] == nil {
                byKey[key] = ProjectFolder(name: name, sortIndex: Int.max / 2)
            }
        }
        return byKey.values.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var groupNames: [String] { folders.map(\.name) }

    func style(forGroup name: String) -> ProjectFolder {
        let key = ProjectFolder.matchKey(for: name)
        return folderStyles.first { $0.matchKey == key } ?? ProjectFolder(name: name)
    }

    /// Create or restyle a group. When `previousName` differs, every card in the
    /// old group is rewritten to point at the new name.
    func upsertFolder(_ folder: ProjectFolder, previousName: String? = nil) {
        let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = folder
        updated.name = name

        if let previousName, ProjectFolder.matchKey(for: previousName) != updated.matchKey {
            for project in projects(in: previousName) {
                var p = project
                p.group = name
                upsert(p)
            }
            folderStyles.removeAll { $0.matchKey == ProjectFolder.matchKey(for: previousName) }
        }

        if let i = folderStyles.firstIndex(where: { $0.matchKey == updated.matchKey }) {
            updated.sortIndex = folderStyles[i].sortIndex
            folderStyles[i] = updated
        } else {
            updated.sortIndex = (folderStyles.map(\.sortIndex).max() ?? -1) + 1
            folderStyles.append(updated)
        }
        saveFolders()
        rebuild()
    }

    /// Delete a group. Its projects are kept and simply un-grouped (each of
    /// their documents is rewritten without the `grupo:` key).
    func deleteFolder(_ folder: ProjectFolder, keepingProjects: Bool = true) {
        let members = projects(in: folder.name)
        if keepingProjects {
            for project in members {
                var p = project
                p.group = nil
                upsert(p)
            }
        } else {
            for project in members { delete(project) }
        }
        folderStyles.removeAll { $0.matchKey == folder.matchKey }
        saveFolders()
        rebuild()
    }

    private func ensureStyleExists(for name: String?) {
        guard let name, !name.isEmpty else { return }
        let key = ProjectFolder.matchKey(for: name)
        guard !folderStyles.contains(where: { $0.matchKey == key }) else { return }
        var style = ProjectFolder(name: name)
        style.sortIndex = (folderStyles.map(\.sortIndex).max() ?? -1) + 1
        folderStyles.append(style)
        saveFolders()
    }

    // MARK: - Roots

    /// The configured root that contains `folderPath`, if any.
    func coveringRoot(for folderPath: String) -> String? {
        settings.normalizedRoots.first { folderPath == $0 || folderPath.hasPrefix($0 + "/") }
    }

    /// Register the parent of a freshly created project folder as a scan root,
    /// so a card created outside the configured roots doesn't vanish on the next
    /// scan. Returns the root added, or nil when the path is too broad to walk.
    @discardableResult
    func adoptRoot(for folderPath: String) -> String? {
        let parent = (folderPath as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != "/", parent != NSHomeDirectory(),
              parent.split(separator: "/").count >= 2 else { return nil }
        settings.projectRoots = AppSettings.normalize(roots: settings.projectRoots + [parent])
        saveSettings()
        return settings.normalizedRoots.first { parent == $0 || parent.hasPrefix($0 + "/") } ?? parent
    }

    func addRoot(_ path: String) {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return }
        settings.projectRoots = AppSettings.normalize(roots: settings.projectRoots + [expanded])
        saveSettings()
    }

    func removeRoot(_ path: String) {
        settings.projectRoots.removeAll { $0 == path }
        saveSettings()
    }

    func isRootAvailable(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Machine-local

    func monitor(for project: Project) -> String? { local.monitor(for: project.id) }

    func setMonitor(_ displayID: String?, for project: Project) {
        local.setMonitor(displayID, for: project.id)
        saveLocal()
        rebuild()
    }

    func noteLaunch(of project: Project) {
        local.noteLaunch(of: project.id)
        saveLocal()
    }

    func clearRecents() {
        local.clearRecents()
        saveLocal()
    }

    /// Recently launched cards, most recent first (cards that no longer exist
    /// are skipped).
    var recentProjects: [Project] {
        local.recentIDs.compactMap { id in projects.first { $0.id == id } }
    }

    var configFolder: URL { dir }
}
