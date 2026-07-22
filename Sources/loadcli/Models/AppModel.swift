import AppKit
import Combine

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
    @Published var editingProject: Project?   // nil = new
    @Published var newProjectFolderID: UUID?  // folder a new card should land in
    @Published var showFolderEditor = false
    @Published var editingFolder: ProjectFolder?  // nil = new

    /// Folders currently expanded — session-only, so every launch starts with
    /// all folders collapsed (easier to scan the list).
    @Published var expandedFolders: Set<UUID> = []

    unowned let store: Store
    init(store: Store) { self.store = store }

    var hasAccessibility: Bool { Permissions.hasAccessibility() }

    // MARK: Editor
    func newProject(in folderID: UUID? = nil) {
        editingProject = nil
        newProjectFolderID = folderID
        // Expand the target folder so the new card is visible once saved.
        if let id = folderID { expandedFolders.insert(id) }
        showEditor = true
    }
    func edit(_ p: Project) { editingProject = p; newProjectFolderID = nil; showEditor = true }

    func newFolder() { editingFolder = nil; showFolderEditor = true }
    func editFolder(_ f: ProjectFolder) { editingFolder = f; showFolderEditor = true }

    // MARK: Folder expansion (session-only)
    func isFolderExpanded(_ id: UUID) -> Bool { expandedFolders.contains(id) }
    func toggleFolder(_ id: UUID) {
        if expandedFolders.contains(id) { expandedFolders.remove(id) }
        else { expandedFolders.insert(id) }
    }

    // MARK: Launch
    /// Show the pre-launch confirmation (monitor + CLI/model/effort), or launch
    /// straight away with the saved preferences when the user turned it off.
    func requestLaunch(_ project: Project) {
        guard !isRunning else { return }
        if store.settings.alwaysAskMonitor {
            pendingProject = project
            showLaunchConfirm = true
            return
        }
        let display = project.monitorPreference.flatMap { DisplayManager.display(withUUID: $0) }
            ?? DisplayManager.main()
        if let display { launch(project, on: display) }
    }

    /// Launch `project` on `display`, persisting whatever was changed in the
    /// confirmation dialog (including the chosen monitor) so the next launch
    /// opens pre-configured the same way.
    func launch(_ project: Project, on display: DisplayInfo) {
        showLaunchConfirm = false
        pendingProject = nil

        var updated = project
        updated.monitorPreference = display.id
        if store.projects.first(where: { $0.id == updated.id }) != updated {
            store.upsert(updated)
        }

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
