import SwiftUI
import AppKit

@main
struct LoadCLIApp: App {
    @StateObject private var store: Store
    @StateObject private var model: AppModel

    init() {
        let s = Store()
        _store = StateObject(wrappedValue: s)
        _model = StateObject(wrappedValue: AppModel(store: s))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 540)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Sobre o loadcli") { Self.showAbout() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Adicionar Projeto…") { model.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView().environmentObject(store)
        }

        MenuBarExtra("loadcli", systemImage: "terminal.fill") {
            MenuBarContent()
                .environmentObject(store)
                .environmentObject(model)
        }
    }

    static func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let body = """
        Lançador de workspaces de desenvolvimento.

        Escolha um projeto e tenha, com um clique: uma nova mesa no monitor que você quiser, o Terminal já com seu CLI rodando na pasta certa e o navegador aberto na página de deploy — lado a lado.

        KamedaTec · github.com/nhkameda/loadcli
        """
        let credits = NSAttributedString(
            string: body,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "loadcli",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 KamedaTec. Todos os direitos reservados.",
        ])
    }
}
