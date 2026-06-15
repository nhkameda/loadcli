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
    @Published var showMonitorPicker = false
    @Published var showEditor = false
    @Published var editingProject: Project?   // nil = new

    unowned let store: Store
    init(store: Store) { self.store = store }

    var hasAccessibility: Bool { Permissions.hasAccessibility() }

    // MARK: Editor
    func newProject() { editingProject = nil; showEditor = true }
    func edit(_ p: Project) { editingProject = p; showEditor = true }

    // MARK: Launch
    /// Decide whether to ask which monitor, then launch.
    func requestLaunch(_ project: Project) {
        guard !isRunning else { return }
        let displays = DisplayManager.displays()

        if let prefID = project.monitorPreference,
           let pref = DisplayManager.display(withUUID: prefID) {
            launch(project, on: pref); return
        }
        if displays.count <= 1 {
            if let only = displays.first ?? DisplayManager.main() { launch(project, on: only) }
            return
        }
        if store.settings.alwaysAskMonitor {
            pendingProject = project
            showMonitorPicker = true
        } else if let main = DisplayManager.main() {
            launch(project, on: main)
        }
    }

    func launch(_ project: Project, on display: DisplayInfo) {
        showMonitorPicker = false
        pendingProject = nil
        Task { await run(project, on: display) }
    }

    private func run(_ project: Project, on display: DisplayInfo) async {
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
    }
}
