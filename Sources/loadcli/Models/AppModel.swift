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

    unowned let store: Store
    init(store: Store) { self.store = store }

    var hasAccessibility: Bool { Permissions.hasAccessibility() }

    // MARK: Editor
    func newProject(in folderID: UUID? = nil) {
        editingProject = nil
        newProjectFolderID = folderID
        showEditor = true
    }
    func edit(_ p: Project) { editingProject = p; newProjectFolderID = nil; showEditor = true }

    func newFolder() { editingFolder = nil; showFolderEditor = true }
    func editFolder(_ f: ProjectFolder) { editingFolder = f; showFolderEditor = true }

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
                _ = await WindowPositioner.focusVerified(
                    tw, appBundleID: AppCatalog.terminalBundleID(forName: updated.terminalApp),
                    appName: updated.terminalApp)
            }
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
