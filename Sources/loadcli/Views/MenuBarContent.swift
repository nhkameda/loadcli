import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var model: AppModel

    var body: some View {
        if store.projects.isEmpty {
            Text("Nenhum projeto").foregroundStyle(.secondary)
        } else {
            ForEach(store.projects) { project in
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    model.requestLaunch(project)
                } label: {
                    Label(project.name, systemImage: project.iconSymbol)
                }
            }
        }

        Divider()

        Button("Adicionar Projeto…") {
            NSApp.activate(ignoringOtherApps: true)
            model.newProject()
        }
        Button("Abrir loadcli") {
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Sair") { NSApp.terminate(nil) }
    }
}
