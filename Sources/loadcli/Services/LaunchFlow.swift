import AppKit

/// The end-to-end workspace launch: new desktop → terminal+CLI → browser+URL → split.
@MainActor
enum LaunchFlow {
    struct Outcome {
        var notice: String? = nil
        var error: String? = nil
        var spaceID: UInt64? = nil   // the desktop that was created (if any)
        var terminalWindow: WindowPositioner.TrackedWindow? = nil   // for late focus
    }

    static func run(_ project: Project, on display: DisplayInfo, settings: AppSettings,
                    progress: @escaping (String) -> Void) async -> Outcome {
        var outcome = Outcome()

        guard Permissions.hasAccessibility() else {
            outcome.error = "Permita o acesso de Acessibilidade ao loadcli em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade."
            Permissions.requestAccessibility()
            return outcome
        }

        // 1. New desktop (mesa) on the chosen monitor. `targetSpaceID` is only
        //    set when we both created AND switched to it — window placement is
        //    verified against that Space id later.
        var targetSpaceID: UInt64? = nil
        if project.workspaceMode == .newDesktop {
            progress("Criando nova mesa em \(display.name)…")
            switch await SpaceManager.createAndEnterDesktop(on: display) {
            case .created(let id):
                targetSpaceID = id
                outcome.spaceID = id
            case .createdNoSwitch(let id):
                outcome.spaceID = id
                outcome.notice = "Mesa criada, mas não consegui alternar para ela automaticamente."
            case .failed:
                outcome.notice = "Não consegui criar a mesa; usei a mesa atual."
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        let terminalBundle = AppCatalog.terminalBundleID(forName: project.terminalApp)
        let hasURL = !project.url.trimmingCharacters(in: .whitespaces).isEmpty

        // 2. Terminal + CLI in the project folder (track which window is new).
        progress("Abrindo \(project.terminalApp) em \(project.folderName)…")
        let termBefore = WindowPositioner.windowIDs(bundleID: terminalBundle)
        let t = await AppLauncher.openTerminal(folder: project.folderPath,
                                               command: project.effectiveCLICommand,
                                               appName: project.terminalApp,
                                               bundleID: terminalBundle)
        if !t.ok { outcome.notice = "Terminal: \(t.error ?? "falha")" }

        // 3. Browser + deploy URL.
        var browserBefore = Set<CGWindowID>()
        if hasURL {
            progress("Abrindo \(project.browserName)…")
            browserBefore = WindowPositioner.windowIDs(bundleID: project.browserBundleID)
            let b = AppLauncher.openBrowser(url: project.url,
                                            bundleID: project.browserBundleID, name: project.browserName)
            if !b.ok { outcome.notice = "Navegador: \(b.error ?? "falha")" }
        }

        // 4. Position the two NEW windows as a split on the target display,
        //    verifying each one actually sits on the new desktop.
        progress("Posicionando janelas…")
        try? await Task.sleep(nanoseconds: UInt64(max(0.3, settings.launchDelaySeconds) * 1_000_000_000))
        let rects = WindowPositioner.halfRects(for: display, leftRatio: project.splitRatio)
        let terminalRect = project.splitSide == .terminalRight ? rects.right : rects.left
        let browserRect  = project.splitSide == .terminalRight ? rects.left : rects.right

        if let tw = await WindowPositioner.newWindow(bundleID: terminalBundle, excluding: termBefore) {
            outcome.terminalWindow = tw
            let onSpace = await WindowPositioner.placeVerified(tw, in: terminalRect,
                                                               expectedSpace: targetSpaceID)
            if !onSpace { outcome.notice = "A janela do terminal pode não ter ficado na nova mesa." }
        } else {
            outcome.notice = "Não encontrei a nova janela do terminal para posicionar."
        }
        if hasURL {
            if let bw = await WindowPositioner.newWindow(bundleID: project.browserBundleID,
                                                         excluding: browserBefore) {
                let onSpace = await WindowPositioner.placeVerified(bw, in: browserRect,
                                                                   expectedSpace: targetSpaceID)
                if !onSpace { outcome.notice = "A janela do navegador pode não ter ficado na nova mesa." }
            } else {
                outcome.notice = "Não encontrei a nova janela do navegador para posicionar."
            }
        }

        // 5. Bring the terminal window to its app's front. App ACTIVATION
        //    happens later (AppModel), after our overlay closed — activating
        //    here gets undone when the launcher UI wraps up.
        if let tw = outcome.terminalWindow {
            WindowPositioner.raise(tw)
        }

        progress("Pronto!")
        return outcome
    }
}
