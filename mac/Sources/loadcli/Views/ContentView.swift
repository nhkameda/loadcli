import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    /// Where the keyboard is: the quick search field or the card grid.
    private enum FocusArea: Hashable { case search, grid }
    @FocusState private var focus: FocusArea?

    @State private var permissionTick = 0
    @State private var confirmingDeleteSelection = false
    @State private var columnCount = 3

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !model.hasAccessibility {
                    permissionBanner
                }
                if let notice = store.migrationNotice {
                    migrationBanner(notice)
                }
                topBar
                Divider()
                content
            }

            if model.isRunning {
                LaunchOverlayView()
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Label("loadcli", systemImage: "terminal.fill").font(.headline)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reescanear as pastas de projetos")
                .disabled(store.isScanning)

                Button { model.newFolder() } label: {
                    Label("Nova Pasta", systemImage: "folder.badge.plus")
                }
                .help("Criar uma pasta para agrupar projetos")

                Button { model.newProject() } label: {
                    Label("Adicionar Projeto", systemImage: "plus")
                }
                .help("Registrar um projeto a partir de uma pasta existente")
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button { model.newProjectQuick() } label: {
                    Label("Novo Projeto", systemImage: "plus.rectangle.on.folder")
                }
                .help("Criar a pasta do projeto e abrir o terminal nela")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .background(hiddenShortcuts)
        .sheet(isPresented: $model.showEditor) {
            ProjectEditorView(seed: model.editorSeed, isNew: model.editorIsNew)
                .environmentObject(store)
        }
        .sheet(isPresented: $model.showFolderEditor) {
            FolderEditorView(folder: model.editingFolder)
                .environmentObject(store)
        }
        .sheet(isPresented: $model.showNewProjectQuick) {
            NewProjectQuickView(presetGroup: model.quickProjectGroup) { name, folderPath, config, layout, group, display in
                model.createQuickProject(name: name, folderPath: folderPath, config: config,
                                         layout: layout, group: group, on: display)
            }
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
        .alert("Problema com o arquivo do projeto", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
        .alert("Excluir o card selecionado?", isPresented: $confirmingDeleteSelection) {
            Button("Excluir card", role: .destructive) {
                if let id = model.selectedProjectID, let p = store.project(withID: id) {
                    store.delete(p)
                    model.selectedProjectID = nil
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O arquivo LOADCLI.md vai para o Lixo. A pasta do projeto continua intacta.")
        }
        .onChange(of: model.searchText) { _, _ in model.searchTextChanged() }
        .onChange(of: model.focusGridTick) { _, _ in focus = .grid }
        .task {
            // The cache already painted the cards; this confirms them against
            // what is really on disk, in the background.
            if store.settings.scanOnLaunch { await store.refresh() }
        }
    }

    // MARK: - Top bar (tabs + quick search)

    private var topBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.tab) {
                ForEach(MainTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            searchField

            if store.isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Atualizando…").font(.caption).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if !store.unavailableRoots.isEmpty {
                Label("\(store.unavailableRoots.count) pasta(s) indisponível(is)",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(store.unavailableRoots.joined(separator: "\n"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animation(.default, value: store.isScanning)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("Buscar projeto", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onSubmit { model.launchSelectionOrFirst(in: visibleProjects) }
            if model.isSearching {
                Button {
                    model.searchText = ""
                    model.searchTextChanged()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Limpar a busca (fecha todas as pastas)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.25)))
        .frame(maxWidth: 320)
    }

    /// Keyboard-only actions that have no visible control.
    private var hiddenShortcuts: some View {
        Group {
            Button("") { model.launchSelection() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(focus == .search || model.selectedProjectID == nil)
            Button("") { focus = .search }
                .keyboardShortcut("f", modifiers: .command)
            Button("") {
                if model.selectedProjectID != nil { confirmingDeleteSelection = true }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(focus == .search || model.selectedProjectID == nil)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .projects: projectsTab
        case .recents:  recentsTab
        }
    }

    @ViewBuilder private var projectsTab: some View {
        if store.settings.projectRoots.isEmpty && store.projects.isEmpty {
            NoRootsView(onChooseFolder: { openSettings() },
                        onNew: { model.newProjectQuick() })
        } else if store.projects.isEmpty {
            EmptyStateView(onNew: { model.newProjectQuick() },
                           onAdd: { model.newProject() },
                           onAddFolder: { model.newFolder() })
        } else {
            let ungrouped = model.filter(store.projects(in: nil))
            let sections = store.folders.map { folder in
                (folder: folder, projects: model.filter(store.projects(in: folder.name)))
            }
            let visibleSections = model.isSearching
                ? sections.filter { !$0.projects.isEmpty }
                : sections

            if model.isSearching && ungrouped.isEmpty && visibleSections.isEmpty {
                NoResultsView(term: model.searchText) { model.searchText = ""; model.searchTextChanged() }
            } else {
                gridScroll {
                    if !ungrouped.isEmpty {
                        if !visibleSections.isEmpty {
                            Text("Sem pasta")
                                .font(.headline).foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                        ProjectGridView(projects: ungrouped)
                    }
                    ForEach(visibleSections, id: \.folder.id) { section in
                        FolderSectionView(folder: section.folder, projects: section.projects)
                    }
                }
            }
        }
    }

    @ViewBuilder private var recentsTab: some View {
        let recents = model.filter(store.recentProjects)
        if recents.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Nenhum projeto aberto ainda").font(.title3).bold()
                Text("Os projetos que você iniciar aparecem aqui, do mais recente para o mais antigo.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            gridScroll {
                HStack {
                    Text("Abertos recentemente")
                        .font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Limpar histórico") { store.clearRecents() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
                .padding(.leading, 2)
                ProjectGridView(projects: recents)
            }
        }
    }

    /// Shared scroll container: keyboard navigation lives here.
    private func gridScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // Build once here: GeometryReader's closure escapes, so it can't hold a
        // non-escaping ViewBuilder.
        let body = content()
        return GeometryReader { geo in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    body
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .grid)
            .onKeyPress(.leftArrow)  { moveSelection(by: -1); return .handled }
            .onKeyPress(.rightArrow) { moveSelection(by: 1); return .handled }
            .onKeyPress(.upArrow)    { moveSelection(by: -columnCount); return .handled }
            .onKeyPress(.downArrow)  { moveSelection(by: columnCount); return .handled }
            .onAppear { updateColumns(for: geo.size.width) }
            .onChange(of: geo.size.width) { _, width in updateColumns(for: width) }
        }
    }

    private func updateColumns(for width: CGFloat) {
        let usable = max(0, width - 40)
        columnCount = max(1, Int((usable + ProjectGridView.spacing)
                                / (ProjectGridView.minCardWidth + ProjectGridView.spacing)))
    }

    /// Every card currently on screen, in display order — the list arrow keys
    /// walk through.
    private var visibleProjects: [Project] {
        if model.tab == .recents { return model.filter(store.recentProjects) }
        var list = model.filter(store.projects(in: nil))
        for folder in store.folders {
            let inFolder = model.filter(store.projects(in: folder.name))
            guard !inFolder.isEmpty, model.isFolderExpanded(folder.name) else { continue }
            list.append(contentsOf: inFolder)
        }
        return list
    }

    private func moveSelection(by delta: Int) {
        let list = visibleProjects
        guard !list.isEmpty else { return }
        guard let current = model.selectedProjectID,
              let index = list.firstIndex(where: { $0.id == current }) else {
            model.selectedProjectID = list.first?.id
            return
        }
        let next = min(max(0, index + delta), list.count - 1)
        model.selectedProjectID = list[next].id
    }

    // MARK: - Banners

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

    private func migrationBanner(_ notice: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Projetos migrados para LOADCLI.md").font(.subheadline).bold()
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Ver pastas") { openSettings() }
            Button("OK") { store.migrationNotice = nil }
        }
        .padding(12)
        .background(.blue.opacity(0.10))
        .overlay(Divider(), alignment: .bottom)
    }

    private func reloadPermissions() {
        permissionTick += 1
        model.objectWillChange.send()
    }
}

/// Shown before any project folder has been registered.
struct NoRootsView: View {
    var onChooseFolder: () -> Void
    var onNew: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nenhuma pasta de projetos cadastrada").font(.title2).bold()
            Text("Aponte o loadcli para as pastas onde seus projetos ficam (por exemplo ~/DEV).\nEle procura um arquivo LOADCLI.md dentro de cada subpasta e monta os cards sozinho —\nse a pasta estiver sincronizada, os mesmos cards aparecem em todos os seus Macs.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button { onNew() } label: {
                    Label("Novo Projeto", systemImage: "plus.rectangle.on.folder")
                }
                .controlSize(.large)
                Button { onChooseFolder() } label: {
                    Label("Cadastrar pasta de projetos", systemImage: "folder.badge.plus")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct NoResultsView: View {
    let term: String
    var onClear: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nada encontrado para “\(term)”").font(.title3).bold()
            Button("Limpar a busca") { onClear() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct EmptyStateView: View {
    var onNew: () -> Void
    var onAdd: () -> Void
    var onAddFolder: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nenhum projeto ainda").font(.title2).bold()
            Text("Crie um projeto novo — a pasta é criada, o LOADCLI.md é gravado nela e o Terminal abre —\nou adicione um projeto a partir de uma pasta existente.")
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
                Button { onNew() } label: {
                    Label("Novo Projeto", systemImage: "plus.rectangle.on.folder")
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

    static let minCardWidth: CGFloat = 250
    static let spacing: CGFloat = 16

    private let columns = [GridItem(.adaptive(minimum: ProjectGridView.minCardWidth,
                                              maximum: 320), spacing: ProjectGridView.spacing)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: ProjectGridView.spacing) {
            ForEach(projects) { project in
                ProjectCardView(
                    project: project,
                    isSelected: model.selectedProjectID == project.id,
                    onSelect: { model.select(project) },
                    onLaunch: { model.requestLaunch(project) },
                    onEdit: { model.edit(project) },
                    onDuplicate: { model.duplicate(project) },
                    onDelete: { store.delete(project) },
                    onRevealFolder: { model.revealFolder(project) },
                    onOpenWebsite: { model.openWebsite(project) },
                    onOpenRepository: { model.openRepository(project) },
                    folders: store.folders,
                    onMove: { store.setGroup($0, for: project) }
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

    private var expanded: Bool { model.isFolderExpanded(folder.name) }

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
            Button { model.toggleFolder(folder.name) } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .disabled(model.isSearching)

            Image(systemName: folder.iconSymbol).foregroundStyle(accent)
            Text(folder.name.isEmpty ? "Pasta" : folder.name).font(.headline)
            Text("\(projects.count)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12), in: Capsule())

            Spacer()

            Button { model.newProjectQuick(in: folder.name) } label: {
                Label("Novo", systemImage: "plus.rectangle.on.folder")
            }
            .buttonStyle(.borderless).font(.callout)
            .help("Criar a pasta do projeto e abrir o terminal, nesta pasta-grupo")

            Menu {
                Button("Criar novo projeto aqui") { model.newProjectQuick(in: folder.name) }
                Button("Adicionar projeto existente aqui") { model.newProject(in: folder.name) }
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
        .onTapGesture { if !model.isSearching { model.toggleFolder(folder.name) } }
    }

    private var emptyHint: some View {
        Button { model.newProjectQuick(in: folder.name) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                Text("Pasta vazia — criar um projeto novo aqui")
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
