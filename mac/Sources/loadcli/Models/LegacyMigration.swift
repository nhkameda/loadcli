import Foundation

/// One-time upgrade from "projects.json is the source of truth" to
/// "every project folder carries its own LOADCLI.md".
///
/// It writes a document into each registered project folder, converts the old
/// UUID-keyed groups into named ones, and seeds the scan roots from the folders
/// the user already had — so the first launch after the update shows exactly the
/// same cards, now backed by files that travel with the folders.
enum LegacyMigration {
    struct Report {
        var documentsWritten: Int = 0
        var projects: [Project] = []
        var folders: [ProjectFolder] = []
        var roots: [String] = []
        var failures: [String] = []

        var isEmpty: Bool { projects.isEmpty && roots.isEmpty }

        /// One-line summary shown in the app's banner.
        var summary: String {
            var parts: [String] = []
            if documentsWritten > 0 {
                parts.append("\(documentsWritten) projeto\(documentsWritten == 1 ? "" : "s") migrado\(documentsWritten == 1 ? "" : "s") para LOADCLI.md")
            }
            if !roots.isEmpty {
                parts.append("\(roots.count) pasta\(roots.count == 1 ? "" : "s") de projetos cadastrada\(roots.count == 1 ? "" : "s")")
            }
            if !failures.isEmpty {
                parts.append("\(failures.count) não puderam ser gravados")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Only the fields the new `Project` no longer carries.
    private struct LegacyRef: Decodable {
        var id: UUID?
        var folderID: UUID?
    }

    private struct LegacyFolder: Decodable {
        var id: UUID?
        var name: String?
        var iconSymbol: String?
        var colorHex: String?
    }

    /// True when there is an old-format `projects.json` still waiting.
    static func isPending(projectsURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: projectsURL.path)
    }

    /// Run the migration. Safe to call when there is nothing to do — it simply
    /// returns an empty report.
    static func run(projectsURL: URL,
                    foldersURL: URL,
                    defaultProjectsFolder: String) -> Report {
        var report = Report()
        let fm = FileManager.default
        guard let projectsData = try? Data(contentsOf: projectsURL) else { return report }

        let decoder = JSONDecoder()
        guard var projects = try? decoder.decode([Project].self, from: projectsData) else { return report }

        // Old group ids → group names.
        var groupNames: [UUID: String] = [:]
        if let foldersData = try? Data(contentsOf: foldersURL),
           let legacyFolders = try? decoder.decode([LegacyFolder].self, from: foldersData) {
            for (index, folder) in legacyFolders.enumerated() {
                guard let id = folder.id else { continue }
                let name = (folder.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                groupNames[id] = name
                report.folders.append(ProjectFolder(name: name,
                                                    iconSymbol: folder.iconSymbol ?? "folder.fill",
                                                    colorHex: folder.colorHex ?? "#64748B",
                                                    sortIndex: index))
            }
        }

        // Re-read the same payload for the fields the new model dropped.
        let refs = (try? decoder.decode([LegacyRef].self, from: projectsData)) ?? []
        var groupByProject: [UUID: String] = [:]
        for ref in refs {
            guard let pid = ref.id, let fid = ref.folderID, let name = groupNames[fid] else { continue }
            groupByProject[pid] = name
        }

        var roots: [String] = []
        for index in projects.indices {
            projects[index].group = groupByProject[projects[index].id]

            let folder = AppSettings.canonical(projects[index].folderPath)
            projects[index].folderPath = folder

            var isDir: ObjCBool = false
            guard !folder.isEmpty, fm.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
                report.failures.append(projects[index].name)
                continue
            }

            // Never clobber a document that already exists (another Mac may have
            // synced it here first) — the file already wins.
            if !ProjectDoc.exists(inFolder: folder) {
                do {
                    try ProjectDoc.write(projects[index])
                    report.documentsWritten += 1
                } catch {
                    report.failures.append(projects[index].name)
                    continue
                }
            }
            if let parent = scanRoot(for: folder) { roots.append(parent) }
        }

        if !defaultProjectsFolder.isEmpty {
            let expanded = (defaultProjectsFolder as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                roots.append(expanded)
            }
        }

        report.projects = projects.filter { !$0.folderPath.isEmpty }
        report.roots = AppSettings.normalize(roots: roots)

        // Keep the old files around, out of the way, so nothing is unrecoverable.
        archive(projectsURL, fm: fm)
        archive(foldersURL, fm: fm)

        return report
    }

    /// The folder to register as a scan root for a project living at `folder`:
    /// its parent, unless that would mean scanning the home directory or a
    /// system-level path.
    private static func scanRoot(for folder: String) -> String? {
        let parent = (folder as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != "/" else { return nil }
        let home = NSHomeDirectory()
        // `~` and `/Users` are far too broad to walk.
        if parent == home || parent == "/Users" || !parent.contains("/") { return nil }
        if parent.split(separator: "/").count < 2 { return nil }
        return parent
    }

    private static func archive(_ url: URL, fm: FileManager) {
        guard fm.fileExists(atPath: url.path) else { return }
        let backup = url.appendingPathExtension("bak")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: url, to: backup)
    }
}
