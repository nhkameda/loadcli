import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var model: AppModel
    @State private var permissionTick = 0

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !model.hasAccessibility {
                    permissionBanner
                }
                content
            }

            if model.isRunning {
                LaunchOverlayView()
            }
        }
        .frame(minWidth: 780, minHeight: 540)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Label("loadcli", systemImage: "terminal.fill").font(.headline)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { reloadPermissions() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reverificar permissões")

                Button { model.newProject() } label: {
                    Label("Adicionar Projeto", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $model.showEditor) {
            ProjectEditorView(project: model.editingProject)
                .environmentObject(store)
        }
        .sheet(isPresented: $model.showMonitorPicker) {
            if let p = model.pendingProject {
                MonitorPickerView(project: p) { display in
                    model.launch(p, on: display)
                } onCancel: {
                    model.showMonitorPicker = false
                    model.pendingProject = nil
                }
            }
        }
        .alert("Não foi possível iniciar", isPresented: Binding(
            get: { model.errorText != nil },
            set: { if !$0 { model.errorText = nil } }
        )) {
            Button("Abrir Acessibilidade") { Permissions.openAccessibilitySettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorText ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        if store.projects.isEmpty {
            EmptyStateView { model.newProject() }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.projects) { project in
                        ProjectCardView(
                            project: project,
                            onLaunch: { model.requestLaunch(project) },
                            onEdit: { model.edit(project) },
                            onDuplicate: { store.duplicate(project) },
                            onDelete: { store.delete(project) }
                        )
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Permissão de Acessibilidade necessária").font(.subheadline).bold()
                Text("O loadcli precisa dela para criar mesas e posicionar as janelas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir Ajustes") { Permissions.openAccessibilitySettings() }
            Button("Já permiti") { reloadPermissions() }
        }
        .padding(12)
        .background(.orange.opacity(0.12))
        .overlay(Divider(), alignment: .bottom)
    }

    private func reloadPermissions() {
        permissionTick += 1
        model.objectWillChange.send()
    }
}

struct EmptyStateView: View {
    var onAdd: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nenhum projeto ainda").font(.title2).bold()
            Text("Adicione um projeto para abrir, com um clique, o Terminal com seu CLI\ne o navegador na página de deploy — em uma nova mesa.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { onAdd() } label: {
                Label("Adicionar Projeto", systemImage: "plus")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
