import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var model: AppModel

    var body: some View {
        if store.projects.isEmpty {
            Text("Nenhum projeto").foregroundStyle(.secondary)
        } else {
            let ungrouped = store.projects(in: nil)
            ForEach(ungrouped) { project in launchButton(project) }
            ForEach(store.folders) { folder in
                let inFolder = store.projects(in: folder.id)
                if !inFolder.isEmpty {
                    Menu {
                        ForEach(inFolder) { project in launchButton(project) }
                    } label: {
                        Label(folder.name.isEmpty ? "Pasta" : folder.name, systemImage: folder.iconSymbol)
                    }
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

    private func launchButton(_ project: Project) -> some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            model.requestLaunch(project)
        } label: {
            Label(project.name, systemImage: project.iconSymbol)
        }
    }
}
