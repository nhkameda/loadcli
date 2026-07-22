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
        //    verified against that Space id later. Skipped for native full
        //    screen, which makes its own Space.
        var targetSpaceID: UInt64? = nil
        if project.createsNewDesktop {
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
        let pane = project.secondaryPane
        let hasPane = pane != .none

        // 2. Terminal + CLI in the project folder (track which window is new).
        progress("Abrindo \(project.terminalApp) em \(project.folderName)…")
        let termBefore = WindowPositioner.windowIDs(bundleID: terminalBundle)
        let t = await AppLauncher.openTerminal(folder: project.folderPath,
                                               command: project.effectiveCLICommand,
                                               appName: project.terminalApp,
                                               bundleID: terminalBundle)
        if !t.ok { outcome.notice = "Terminal: \(t.error ?? "falha")" }

        // 3. Secondary pane (browser at the deploy URL, or Finder at a folder).
        var paneBundle = ""
        var paneBefore = Set<CGWindowID>()
        switch pane {
        case .browser:
            progress("Abrindo \(project.browserName)…")
            paneBundle = project.browserBundleID
            paneBefore = WindowPositioner.windowIDs(bundleID: paneBundle)
            let b = AppLauncher.openBrowser(url: project.url,
                                            bundleID: paneBundle, name: project.browserName)
            if !b.ok { outcome.notice = "Navegador: \(b.error ?? "falha")" }
        case .finder:
            paneBundle = "com.apple.finder"
            let target = project.effectiveFinderPath
            progress("Abrindo Finder em \((target as NSString).lastPathComponent)…")
            paneBefore = WindowPositioner.windowIDs(bundleID: paneBundle)
            let f = AppLauncher.openFinder(path: target)
            if !f.ok { outcome.notice = "Finder: \(f.error ?? "falha")" }
        case .none:
            break
        }

        // 4. Position the NEW windows on the target display, verifying each one
        //    actually sits on the new desktop. With no secondary pane the
        //    terminal takes the whole mesa; otherwise they split.
        progress("Posicionando janelas…")
        try? await Task.sleep(nanoseconds: UInt64(max(0.3, settings.launchDelaySeconds) * 1_000_000_000))

        // 4a. Terminal-only + native full screen: move the window onto the
        //     chosen monitor, then toggle full screen — which gives it its own
        //     Space there, so no mesa was created above.
        if project.wantsSoloFullscreen {
            progress("Deixando o terminal em tela cheia…")
            if let tw = await WindowPositioner.newWindow(bundleID: terminalBundle, excluding: termBefore) {
                outcome.terminalWindow = tw
                WindowPositioner.place(tw.element, in: DisplayManager.cocoaToCG(display.visibleFrame))
                try? await Task.sleep(nanoseconds: 350_000_000)
                if !WindowPositioner.enterFullscreen(tw) {
                    outcome.notice = "Abri o terminal, mas não consegui ativar a tela cheia."
                }
            } else {
                outcome.notice = "Não encontrei a nova janela do terminal para posicionar."
            }
            progress("Pronto!")
            return outcome
        }

        // 4b. Split (with a pane) or maximize (terminal-only).
        let rects = WindowPositioner.halfRects(for: display, leftRatio: project.splitRatio)
        let terminalRect: CGRect
        let paneRect: CGRect
        if hasPane {
            terminalRect = project.splitSide == .terminalRight ? rects.right : rects.left
            paneRect     = project.splitSide == .terminalRight ? rects.left  : rects.right
        } else {
            terminalRect = DisplayManager.cocoaToCG(display.visibleFrame)
            paneRect = .zero
        }

        if let tw = await WindowPositioner.newWindow(bundleID: terminalBundle, excluding: termBefore) {
            outcome.terminalWindow = tw
            let onSpace = await WindowPositioner.placeVerified(tw, in: terminalRect,
                                                               expectedSpace: targetSpaceID)
            if !onSpace { outcome.notice = "A janela do terminal pode não ter ficado na nova mesa." }
        } else {
            outcome.notice = "Não encontrei a nova janela do terminal para posicionar."
        }
        if hasPane {
            if let pw = await WindowPositioner.newWindow(bundleID: paneBundle, excluding: paneBefore) {
                let onSpace = await WindowPositioner.placeVerified(pw, in: paneRect,
                                                                   expectedSpace: targetSpaceID)
                if !onSpace { outcome.notice = "A janela do \(pane.shortLabel) pode não ter ficado na nova mesa." }
            } else {
                outcome.notice = "Não encontrei a nova janela do \(pane.shortLabel) para posicionar."
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
