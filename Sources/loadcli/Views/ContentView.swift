import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var model: AppModel
    @State private var permissionTick = 0

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

                Button { model.newFolder() } label: {
                    Label("Nova Pasta", systemImage: "folder.badge.plus")
                }
                .help("Criar uma pasta para agrupar projetos")

                Button { model.newProject() } label: {
                    Label("Adicionar Projeto", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $model.showEditor) {
            ProjectEditorView(project: model.editingProject,
                              presetFolderID: model.newProjectFolderID)
                .environmentObject(store)
        }
        .sheet(isPresented: $model.showFolderEditor) {
            FolderEditorView(folder: model.editingFolder)
                .environmentObject(store)
        }
        .sheet(isPresented: $model.showLaunchConfirm) {
            if let p = model.pendingProject {
                LaunchConfirmView(project: p) { project, display in
                    model.launch(project, on: display)
                } onCancel: {
                    model.showLaunchConfirm = false
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
        if store.projects.isEmpty && store.folders.isEmpty {
            EmptyStateView(onAdd: { model.newProject() },
                           onAddFolder: { model.newFolder() })
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    let ungrouped = store.projects(in: nil)
                    if !ungrouped.isEmpty {
                        if !store.folders.isEmpty {
                            Text("Sem pasta")
                                .font(.headline).foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                        ProjectGridView(projects: ungrouped)
                    }
                    ForEach(store.folders) { folder in
                        FolderSectionView(folder: folder,
                                          projects: store.projects(in: folder.id))
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
    var onAddFolder: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nenhum projeto ainda").font(.title2).bold()
            Text("Adicione um projeto para abrir, com um clique, o Terminal com seu CLI\ne — se quiser — o navegador na página de deploy ou uma pasta no Finder, em uma nova mesa.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button { onAddFolder() } label: {
                    Label("Nova Pasta", systemImage: "folder.badge.plus")
                }
                .controlSize(.large)
                Button { onAdd() } label: {
                    Label("Adicionar Projeto", systemImage: "plus")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A responsive grid of project cards, wired to the store/model actions.
struct ProjectGridView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var model: AppModel
    let projects: [Project]

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(projects) { project in
                ProjectCardView(
                    project: project,
                    onLaunch: { model.requestLaunch(project) },
                    onEdit: { model.edit(project) },
                    onDuplicate: { store.duplicate(project) },
                    onDelete: { store.delete(project) },
                    folders: store.folders,
                    onMove: { store.setFolder($0, for: project) }
                )
            }
        }
    }
}

/// One collapsible folder section: header (name, count, add-card, menu) + grid.
struct FolderSectionView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var model: AppModel
    let folder: ProjectFolder
    let projects: [Project]

    private var accent: Color { Color(hex: folder.colorHex) }

    private var expanded: Bool { model.isFolderExpanded(folder.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if expanded {
                if projects.isEmpty {
                    emptyHint
                } else {
                    ProjectGridView(projects: projects)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { model.toggleFolder(folder.id) } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Image(systemName: folder.iconSymbol).foregroundStyle(accent)
            Text(folder.name.isEmpty ? "Pasta" : folder.name).font(.headline)
            Text("\(projects.count)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12), in: Capsule())

            Spacer()

            Button { model.newProject(in: folder.id) } label: {
                Label("Adicionar", systemImage: "plus")
            }
            .buttonStyle(.borderless).font(.callout)

            Menu {
                Button("Adicionar projeto aqui") { model.newProject(in: folder.id) }
                Button("Renomear pasta…") { model.editFolder(folder) }
                Divider()
                Button("Excluir pasta (manter projetos)", role: .destructive) {
                    store.deleteFolder(folder, keepingProjects: true)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggleFolder(folder.id) }
    }

    private var emptyHint: some View {
        Button { model.newProject(in: folder.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                Text("Pasta vazia — adicionar um projeto aqui")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.secondary.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }
}
