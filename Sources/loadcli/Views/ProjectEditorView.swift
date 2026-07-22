import SwiftUI
import AppKit

struct ProjectEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Project
    private let isNew: Bool

    init(project: Project?) {
        _draft = State(initialValue: project ?? Project())
        isNew = (project == nil)
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
                    TextField("Nome", text: $draft.name, prompt: Text("erp-kameda"))
                    iconAndColorRow
                }

                Section("Pasta e CLI") {
                    HStack {
                        TextField("Pasta do projeto", text: $draft.folderPath,
                                  prompt: Text("/Users/você/DEV/erp-kameda"))
                        Button("Escolher…") { chooseFolder() }
                    }
                    CLIConfigSection(project: $draft)
                    Picker("Terminal", selection: $draft.terminalApp) {
                        ForEach(AppCatalog.terminals) { Text($0.name).tag($0.name) }
                    }
                }

                Section("Navegador e deploy") {
                    TextField("URL", text: $draft.url, prompt: Text("https://erp.kamedatec.com"))
                    Picker("Navegador", selection: $draft.browserBundleID) {
                        ForEach(AppCatalog.browsers) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: draft.browserBundleID) { _, new in
                        draft.browserName = AppCatalog.browsers.first { $0.id == new }?.name ?? "Google Chrome"
                    }
                }

                Section("Mesa e janelas") {
                    Picker("Modo", selection: $draft.workspaceMode) {
                        ForEach(WorkspaceMode.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Layout", selection: $draft.splitSide) {
                        ForEach(SplitSide.allCases) { Text($0.label).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Divisão: navegador \(Int(draft.splitRatio * 100))% · terminal \(Int((1 - draft.splitRatio) * 100))%")
                            .font(.caption).foregroundStyle(.secondary)
                        Slider(value: $draft.splitRatio, in: 0.3...0.7, step: 0.05)
                    }
                    Picker("Monitor", selection: monitorBinding) {
                        Text("Perguntar a cada vez").tag(String?.none)
                        ForEach(displays) { d in
                            Text(d.name + (d.isMain ? " (Principal)" : "")).tag(Optional(d.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew {
                    Button("Excluir", role: .destructive) {
                        store.delete(draft); dismiss()
                    }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Adicionar" : "Salvar") {
                    store.upsert(draft); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
            .padding(16)
        }
        .frame(width: 540, height: 640)
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

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        if !draft.folderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: draft.folderPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            draft.folderPath = url.path
            if draft.name.isEmpty { draft.name = url.lastPathComponent }
        }
    }
}
