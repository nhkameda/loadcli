import AppKit
import Combine

/// Which list the main window is showing.
enum MainTab: String, CaseIterable, Identifiable {
    case projects, recents

    var id: String { rawValue }
    var label: String {
        switch self {
        case .projects: return "Projetos"
        case .recents:  return "Recentes"
        }
    }
    var systemImage: String {
        switch self {
        case .projects: return "square.grid.2x2"
        case .recents:  return "clock.arrow.circlepath"
        }
    }
}

/// App-wide controller: owns transient UI state and drives the launch flow.
@MainActor
final class AppModel: ObservableObject {
    // Launch run-state (consumed by the overlay).
    @Published var isRunning = false
    @Published var statusText = ""
    @Published var errorText: String?
    @Published var noticeText: String?

    // Sheets / pickers.
    @Published var pendingProject: Project?
    @Published var showLaunchConfirm = false
    @Published var showEditor = false
    /// Values the project editor starts from (nil while it is closed).
    @Published var editorSeed: Project?
    @Published var editorIsNew = true
    @Published var showFolderEditor = false
    @Published var editingFolder: ProjectFolder?  // nil = new

    // Quick "Novo Projeto": scaffold a fresh folder + launch in one step.
    @Published var showNewProjectQuick = false
    @Published var quickProjectGroup: String?   // group the new card lands in

    // Main list state.
    @Published var tab: MainTab = .projects
    @Published var searchText = ""
    @Published var selectedProjectID: UUID?
    /// Bumped whenever the keyboard focus should move to the card grid, so the
    /// arrow keys work right after a card is clicked.
    @Published private(set) var focusGridTick = 0

    /// Folders currently expanded — session-only, so every launch starts with
    /// all folders collapsed (easier to scan the list). Keyed by group match key.
    @Published var expandedFolders: Set<String> = []

    unowned let store: Store
    init(store: Store) { self.store = store }

    var hasAccessibility: Bool { Permissions.hasAccessibility() }

    // MARK: - Search

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Terms are ANDed, so "acme site" matches a card containing both words.
    private var searchTerms: [String] {
        searchText.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    func matches(_ project: Project) -> Bool {
        let terms = searchTerms
        guard !terms.isEmpty else { return true }
        let haystack = project.searchHaystack
        return terms.allSatisfy { haystack.contains($0) }
    }

    func filter(_ projects: [Project]) -> [Project] {
        isSearching ? projects.filter(matches) : projects
    }

    /// Clearing the search collapses every folder again, as asked.
    func searchTextChanged() {
        if !isSearching {
            expandedFolders.removeAll()
        }
    }

    // MARK: - Editor

    func newProject(in group: String? = nil) {
        var seed = Project()
        seed.group = group
        seed.folderPath = ""
        editorSeed = seed
        editorIsNew = true
        if let group { expandedFolders.insert(ProjectFolder.matchKey(for: group)) }
        showEditor = true
    }

    func edit(_ p: Project) {
        editorSeed = p
        editorIsNew = false
        showEditor = true
    }

    /// "Duplicar" can no longer copy in place (one document per folder), so it
    /// opens the editor pre-filled with a copy that still needs a folder.
    func duplicate(_ p: Project) {
        editorSeed = store.duplicateDraft(of: p)
        editorIsNew = true
        showEditor = true
    }

    // MARK: - Quick "Novo Projeto"

    /// Open the quick-create sheet (name + CLI/model/effort only). The new card
    /// lands in `group` (the section the action was invoked from).
    func newProjectQuick(in group: String? = nil) {
        guard !isRunning else { return }
        quickProjectGroup = group
        if let group { expandedFolders.insert(ProjectFolder.matchKey(for: group)) }
        showNewProjectQuick = true
    }

    /// Create `folderPath` on disk (composed as `<defaultProjectsFolder>/<name>`
    /// in the dialog, but editable), write its LOADCLI.md, and launch it
    /// (terminal-only, maximized or full screen) on `display` — all from the
    /// single "Criar" click.
    func createQuickProject(name: String, folderPath: String, config: Project,
                            layout: SoloTerminalLayout,
                            group: String?, on display: DisplayInfo) {
        showNewProjectQuick = false
        errorText = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard !rawPath.isEmpty else {
            errorText = "Defina a pasta do projeto."
            return
        }

        let dir = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath, isDirectory: true)
        do {
            // `withIntermediateDirectories: true` is a no-op if it already exists
            // (reuse the folder); it only throws on a real filesystem error.
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            errorText = "Não consegui criar a pasta \(dir.path): \(error.localizedDescription)"
            return
        }

        var project = config
        project.name = trimmedName
        project.folderPath = dir.path
        project.group = group
        project.secondaryPane = .none
        project.soloTerminalLayout = layout
        project.monitorPreference = display.id
        if project.repoURL.isEmpty, let remote = ProjectScanner.gitRemote(inFolder: dir.path) {
            project.repoURL = remote
        }
        if let failure = store.upsert(project) {
            errorText = failure
            return
        }

        // Launch straight away — CLI, layout and monitor are already decided, so
        // skip the confirmation dialog.
        launch(project, on: display)
    }

    func newFolder() { editingFolder = nil; showFolderEditor = true }
    func editFolder(_ f: ProjectFolder) { editingFolder = f; showFolderEditor = true }

    // MARK: - Folder expansion (session-only)

    func isFolderExpanded(_ groupName: String) -> Bool {
        // While searching, every section that still has results stays open.
        if isSearching { return true }
        return expandedFolders.contains(ProjectFolder.matchKey(for: groupName))
    }

    func toggleFolder(_ groupName: String) {
        let key = ProjectFolder.matchKey(for: groupName)
        if expandedFolders.contains(key) { expandedFolders.remove(key) }
        else { expandedFolders.insert(key) }
    }

    // MARK: - Scanning

    /// Re-walk the configured roots. Fire-and-forget: the UI keeps showing the
    /// cached cards while it runs.
    func refresh() {
        Task { await store.refresh() }
    }

    // MARK: - Card shortcuts

    func revealFolder(_ project: Project) {
        let path = project.folderPath
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openWebsite(_ project: Project) {
        let raw = project.trimmedURL
        guard !raw.isEmpty else { return }
        open(urlString: raw, in: project.browserBundleID)
    }

    func openRepository(_ project: Project) {
        guard let web = project.repoWebURL else {
            // A local path — reveal it instead.
            let raw = project.trimmedRepo
            if !raw.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: (raw as NSString).expandingTildeInPath),
                ])
            }
            return
        }
        open(urlString: web, in: project.browserBundleID)
    }

    private func open(urlString: String, in browserBundleID: String) {
        let normalized = urlString.contains("://") ? urlString : "https://" + urlString
        guard let url = URL(string: normalized) else { return }
        if let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: browser,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Launch

    /// Show the pre-launch confirmation (monitor + CLI/model/effort), or launch
    /// straight away with the saved preferences when the user turned it off.
    func requestLaunch(_ project: Project) {
        guard !isRunning else { return }
        selectedProjectID = project.id
        if store.settings.alwaysAskMonitor {
            pendingProject = project
            showLaunchConfirm = true
            return
        }
        let display = project.monitorPreference.flatMap { DisplayManager.display(withUUID: $0) }
            ?? DisplayManager.main()
        if let display { launch(project, on: display) }
    }

    /// Select a card and give the grid keyboard focus.
    func select(_ project: Project) {
        selectedProjectID = project.id
        focusGridTick &+= 1
    }

    /// Launch the currently selected card (⏎ in the main list).
    func launchSelection() {
        guard let id = selectedProjectID, let project = store.project(withID: id) else { return }
        requestLaunch(project)
    }

    /// ⏎ from the search field: launch what is selected, or the first result.
    func launchSelectionOrFirst(in visible: [Project]) {
        if let id = selectedProjectID, let project = visible.first(where: { $0.id == id }) {
            requestLaunch(project)
        } else if let first = visible.first {
            requestLaunch(first)
        }
    }

    /// Launch `project` on `display`. The monitor is remembered per machine
    /// (`LocalPrefs`), while any CLI/model/effort change made in the dialog is
    /// written back into the project's LOADCLI.md.
    func launch(_ project: Project, on display: DisplayInfo) {
        showLaunchConfirm = false
        pendingProject = nil

        var updated = project
        updated.monitorPreference = display.id
        store.setMonitor(display.id, for: updated)
        if let stored = store.project(withID: updated.id), stored != updated {
            store.upsert(updated)
        }
        store.noteLaunch(of: updated)
        selectedProjectID = updated.id

        Task {
            let outcome = await run(updated, on: display)
            // Focus the new terminal only AFTER the overlay is gone, so
            // nothing in our own UI re-takes activation.
            if let tw = outcome.terminalWindow {
                try? await Task.sleep(nanoseconds: 600_000_000)
                let terminalBundle = AppCatalog.terminalBundleID(forName: updated.terminalApp)
                let focused = await WindowPositioner.focusVerified(
                    tw, appBundleID: terminalBundle, appName: updated.terminalApp)
                // Only bump the font if the terminal really came to the front —
                // otherwise the ⌘+ keystrokes would hit the wrong app.
                if focused, store.settings.increaseTerminalFont {
                    await bumpTerminalFont(steps: store.settings.terminalFontZoomSteps,
                                           terminalBundle: terminalBundle)
                    // The font bump grows Terminal/iTerm windows (they keep the
                    // column count), so re-assert the tiled rect afterwards.
                    if let rect = outcome.terminalRect {
                        await WindowPositioner.reassertRect(tw, in: rect)
                    }
                }
            }
        }
    }

    /// Mimic the user's ⌘+ presses to enlarge the terminal font, re-checking
    /// before each press that the terminal is still frontmost.
    private func bumpTerminalFont(steps: Int, terminalBundle: String) async {
        let n = max(1, min(20, steps))
        try? await Task.sleep(nanoseconds: 200_000_000)   // let focus settle
        for _ in 0..<n {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == terminalBundle else { return }
            AppLauncher.pressCommandPlus()
            try? await Task.sleep(nanoseconds: 45_000_000)
        }
    }

    @discardableResult
    private func run(_ project: Project, on display: DisplayInfo) async -> LaunchFlow.Outcome {
        isRunning = true
        errorText = nil
        noticeText = nil
        statusText = "Preparando…"
        defer { isRunning = false }

        let outcome = await LaunchFlow.run(project, on: display, settings: store.settings) { [weak self] msg in
            self?.statusText = msg
        }
        errorText = outcome.error
        noticeText = outcome.notice
        return outcome
    }
}
