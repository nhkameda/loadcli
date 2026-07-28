import SwiftUI
import AppKit

/// Create or edit a card. Saving writes the project's `LOADCLI.md` into its own
/// folder — that file is the card, so everything typed here travels with the
/// folder to every machine that syncs it.
struct ProjectEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Project
    @State private var newGroupName = ""
    @State private var notice: String?
    private let isNew: Bool

    /// Marker option in the group picker that reveals the "new group" field.
    private static let newGroupSentinel = "\u{1}novo-grupo"

    init(seed: Project?, isNew: Bool) {
        _draft = State(initialValue: seed ?? Project())
        self.isNew = isNew
    }

    private var displays: [DisplayInfo] { DisplayManager.displays() }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "Novo Projeto" : "Editar Projeto").font(.title2).bold()
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

            Form {
                Section("Identificação") {
                    TextField("Nome", text: $draft.name, prompt: Text("meu-projeto"))
                    groupPicker
                    iconAndColorRow
                }

                Section("Pasta do projeto") {
                    HStack {
                        TextField("Pasta do projeto", text: $draft.folderPath,
                                  prompt: Text("/Users/você/DEV/meu-projeto"))
                            .font(.system(.body, design: .monospaced))
                        Button("Escolher…") { chooseFolder() }
                    }
                    Text("O LOADCLI.md é gravado aqui dentro — é ele que vira o card em qualquer Mac que abra esta pasta.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.blue)
                    }
                }

                Section("Descrição") {
                    TextEditor(text: $draft.details)
                        .font(.body)
                        .frame(minHeight: 70)
                        .scrollContentBackground(.hidden)
                    Text("Aparece no card, em até duas linhas. Aceita markdown livre.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Links") {
                    HStack {
                        TextField("Repositório", text: $draft.repoURL,
                                  prompt: Text("https://github.com/você/projeto"))
                        Button("Detectar") { detectRepository() }
                            .help("Ler a URL do remote origin em .git/config")
                            .disabled(draft.folderPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    TextField("Site do projeto", text: $draft.url,
                              prompt: Text("https://app.exemplo.com"))
                }

                Section("CLI e terminal") {
                    CLIConfigSection(project: $draft)
                    Picker("Terminal", selection: $draft.terminalApp) {
                        ForEach(AppCatalog.terminals) { Text($0.name).tag($0.name) }
                    }
                }

                Section("Ao lado do terminal") {
                    Picker("Painel", selection: secondaryPaneBinding) {
                        ForEach(SecondaryPane.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch draft.secondaryPane {
                    case .none:
                        Picker("Estilo", selection: soloLayoutBinding) {
                            ForEach(SoloTerminalLayout.allCases) { Text($0.shortLabel).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(draft.soloTerminalLayout == .fullscreen
                             ? "Tela cheia nativa no monitor escolhido — cria a própria mesa (não abre uma mesa extra)."
                             : "O terminal preenche o monitor escolhido.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .browser:
                        Picker("Navegador", selection: $draft.browserBundleID) {
                            ForEach(AppCatalog.browsers) { Text($0.name).tag($0.id) }
                        }
                        .onChange(of: draft.browserBundleID) { _, new in
                            draft.browserName = AppCatalog.browsers.first { $0.id == new }?.name ?? "Google Chrome"
                        }
                        Text("Abre o “Site do projeto” configurado acima.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .finder:
                        HStack {
                            TextField("Pasta no Finder", text: $draft.finderPath,
                                      prompt: Text(draft.folderPath.isEmpty
                                                   ? "/Users/você/DEV/meu-projeto" : draft.folderPath))
                            Button("Escolher…") { chooseFinderFolder() }
                        }
                        Text("Se vazio, abre a pasta do projeto.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Mesa e janelas") {
                    if !draft.wantsSoloFullscreen {
                        Picker("Modo", selection: $draft.workspaceMode) {
                            ForEach(WorkspaceMode.allCases) { Text($0.label).tag($0) }
                        }
                    } else {
                        LabeledContent("Modo", value: "Tela cheia (mesa própria)")
                    }
                    if draft.secondaryPane != .none {
                        Picker("Layout", selection: $draft.splitSide) {
                            ForEach(SplitSide.allCases) { Text($0.label).tag($0) }
                        }
                        VStack(alignment: .leading) {
                            Text("Divisão: terminal \(terminalPercent)% · painel \(100 - terminalPercent)%")
                                .font(.caption).foregroundStyle(.secondary)
                            Slider(value: $draft.splitRatio, in: 0.3...0.7, step: 0.05)
                        }
                    }
                    Picker("Monitor", selection: monitorBinding) {
                        Text("Perguntar a cada vez").tag(String?.none)
                        ForEach(displays) { d in
                            Text(d.name + (d.isMain ? " (Principal)" : "")).tag(Optional(d.id))
                        }
                    }
                    Text("O monitor fica salvo só neste Mac — não vai para o LOADCLI.md.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew {
                    Button("Excluir card", role: .destructive) {
                        store.delete(draft); dismiss()
                    }
                    .help("Manda o LOADCLI.md para o Lixo; a pasta do projeto continua intacta.")
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Adicionar" : "Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isValid)
            }
            .padding(16)
        }
        .frame(width: 560, height: 700)
    }

    // MARK: Group

    private var groupPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Pasta (grupo)", selection: groupBinding) {
                Text("Sem pasta").tag(String?.none)
                ForEach(store.groupNames, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
                Divider()
                Text("Nova pasta…").tag(Optional(Self.newGroupSentinel))
            }
            if draft.group == Self.newGroupSentinel {
                TextField("Nome da nova pasta", text: $newGroupName, prompt: Text("Clientes"))
            }
        }
    }

    private var groupBinding: Binding<String?> {
        Binding(get: { draft.group }, set: { draft.group = $0 })
    }

    /// The group actually saved — resolving the "nova pasta" placeholder.
    private var resolvedGroup: String? {
        if draft.group == Self.newGroupSentinel {
            let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return draft.groupName
    }

    // MARK: Actions

    private func save() {
        var project = draft
        project.group = resolvedGroup
        if let failure = store.upsert(project) {
            store.lastError = failure
            return
        }
        dismiss()
    }

    private func detectRepository() {
        let folder = (draft.folderPath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if let remote = ProjectScanner.gitRemote(inFolder: folder) {
            draft.repoURL = remote
            notice = "Repositório lido de .git/config."
        } else {
            notice = "Nenhum remote git encontrado nessa pasta."
        }
    }

    private var iconAndColorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ícone").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 8) {
                ForEach(IconCatalog.symbols, id: \.self) { sym in
                    Image(systemName: sym)
                        .frame(width: 26, height: 26)
                        .background(draft.iconSymbol == sym ? Color(hex: draft.colorHex).opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(draft.iconSymbol == sym ? Color(hex: draft.colorHex) : .clear))
                        .onTapGesture { draft.iconSymbol = sym }
                }
            }
            Text("Cor").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(IconCatalog.colors, id: \.self) { hex in
                    Circle().fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(.primary, lineWidth: draft.colorHex == hex ? 2 : 0))
                        .onTapGesture { draft.colorHex = hex }
                }
            }
        }
    }

    private var monitorBinding: Binding<String?> {
        Binding(get: { draft.monitorPreference }, set: { draft.monitorPreference = $0 })
    }

    private var secondaryPaneBinding: Binding<SecondaryPane> {
        Binding(get: { draft.secondaryPane }, set: { draft.secondaryPane = $0 })
    }

    private var soloLayoutBinding: Binding<SoloTerminalLayout> {
        Binding(get: { draft.soloTerminalLayout }, set: { draft.soloTerminalLayout = $0 })
    }

    /// Percentage of the split the terminal gets, honouring which side it's on.
    private var terminalPercent: Int {
        let frac = draft.splitSide == .terminalRight ? (1 - draft.splitRatio) : draft.splitRatio
        return Int((frac * 100).rounded())
    }

    private func chooseFolder() {
        pickFolder(startingAt: draft.folderPath) { url in
            draft.folderPath = url.path
            if draft.name.isEmpty { draft.name = url.lastPathComponent }
            adoptExistingDocument(at: url.path)
        }
    }

    /// A folder that already carries a LOADCLI.md wins: load it instead of
    /// creating a second, conflicting card for the same project.
    private func adoptExistingDocument(at folder: String) {
        guard ProjectDoc.exists(inFolder: folder),
              let doc = ProjectDoc.read(inFolder: folder) else {
            if draft.repoURL.trimmingCharacters(in: .whitespaces).isEmpty,
               let remote = ProjectScanner.gitRemote(inFolder: folder) {
                draft.repoURL = remote
            }
            return
        }
        var loaded = doc.project
        // Keep the identity we are already editing when it is an existing card.
        if !isNew { loaded.id = draft.id }
        draft = loaded
        notice = "Esta pasta já tem um LOADCLI.md — os dados foram carregados dele."
    }

    private func chooseFinderFolder() {
        pickFolder(startingAt: draft.finderPath.isEmpty ? draft.folderPath : draft.finderPath) { url in
            draft.finderPath = url.path
        }
    }

    private func pickFolder(startingAt path: String, _ apply: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path) }
        if panel.runModal() == .OK, let url = panel.url { apply(url) }
    }
}
