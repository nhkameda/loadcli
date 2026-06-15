import AppKit

/// The end-to-end workspace launch: new desktop → terminal+CLI → browser+URL → split.
@MainActor
enum LaunchFlow {
    struct Outcome { var notice: String? = nil; var error: String? = nil }

    static func run(_ project: Project, on display: DisplayInfo, settings: AppSettings,
                    progress: @escaping (String) -> Void) async -> Outcome {
        var outcome = Outcome()

        guard Permissions.hasAccessibility() else {
            outcome.error = "Permita o acesso de Acessibilidade ao loadcli em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade."
            Permissions.requestAccessibility()
            return outcome
        }

        // 1. New desktop (mesa) on the chosen monitor.
        if project.workspaceMode == .newDesktop {
            progress("Criando nova mesa em \(display.name)…")
            switch await SpaceManager.createAndEnterDesktop(on: display) {
            case .created: break
            case .createdNoSwitch:
                outcome.notice = "Mesa criada, mas não consegui alternar para ela automaticamente."
            case .failed:
                outcome.notice = "Não consegui criar a mesa; usei a mesa atual."
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // 2. Terminal + CLI in the project folder.
        progress("Abrindo \(project.terminalApp) em \(project.folderName)…")
        let t = AppLauncher.openTerminal(folder: project.folderPath,
                                         command: project.cliCommand, appName: project.terminalApp)
        if !t.ok { outcome.notice = "Terminal: \(t.error ?? "falha")" }

        // 3. Browser + deploy URL.
        let hasURL = !project.url.trimmingCharacters(in: .whitespaces).isEmpty
        if hasURL {
            progress("Abrindo \(project.browserName)…")
            let b = AppLauncher.openBrowser(url: project.url,
                                            bundleID: project.browserBundleID, name: project.browserName)
            if !b.ok { outcome.notice = "Navegador: \(b.error ?? "falha")" }
        }

        // 4. Position the two windows as a split on the target display.
        progress("Posicionando janelas…")
        try? await Task.sleep(nanoseconds: UInt64(max(0.3, settings.launchDelaySeconds) * 1_000_000_000))
        let rects = WindowPositioner.halfRects(for: display, leftRatio: project.splitRatio)
        let terminalRect = project.splitSide == .terminalRight ? rects.right : rects.left
        let browserRect  = project.splitSide == .terminalRight ? rects.left : rects.right

        if let tw = await WindowPositioner.frontWindow(
            bundleID: AppCatalog.terminalBundleID(forName: project.terminalApp)) {
            WindowPositioner.place(tw, in: terminalRect)
        }
        if hasURL, let bw = await WindowPositioner.frontWindow(bundleID: project.browserBundleID) {
            WindowPositioner.place(bw, in: browserRect)
        }

        progress("Pronto!")
        return outcome
    }
}
