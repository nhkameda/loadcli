import SwiftUI
import AppKit

/// Quick "Novo Projeto": asks only for the name, group and CLI/model/effort
/// (and, when there is more than one monitor, where to open). The project folder
/// is auto-composed as `<pasta padrão>/<nome>` — pre-filled and editable. On
/// "Criar" it scaffolds that folder on disk, writes its `LOADCLI.md` and
/// launches the terminal in it, maximized or full screen.
struct NewProjectQuickView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    /// (name, project-folder path, cli-config draft, layout, group, display).
    var onCreate: (String, String, Project, SoloTerminalLayout, String?, DisplayInfo) -> Void

    @State private var name = ""
    @State private var folderPath = ""            // the project folder to create
    @State private var pathEdited = false         // user hand-edited the full path
    @State private var baseOverride: String?      // parent chosen via "Escolher…"
    @State private var draft = Project()          // holds the CLI/model/effort choices
    @State private var layout: SoloTerminalLayout = .maximized
    @State private var selectedDisplayID: String
    @State private var group: String?
    @State private var newGroupName = ""

    /// Marker option in the group picker that reveals the "new group" field.
    private static let newGroupSentinel = "\u{1}novo-grupo"

    private let displays: [DisplayInfo]

    init(presetGroup: String? = nil,
         onCreate: @escaping (String, String, Project, SoloTerminalLayout, String?, DisplayInfo) -> Void) {
        self.onCreate = onCreate
        let all = DisplayManager.displays()
        displays = all
        let main = all.first { $0.isMain } ?? all.first
        _selectedDisplayID = State(initialValue: main?.id ?? "")
        _group = State(initialValue: presetGroup)
    }

    /// Parent folder the name is appended to — a per-project override, else the
    /// global default configured in Settings.
    private var base: String {
        (baseOverride ?? store.settings.defaultProjectsFolder)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// `<base>/<name>` — what the folder field auto-fills to while untouched.
    private var derivedPath: String {
        guard !base.isEmpty else { return "" }
        return trimmedName.isEmpty ? base : (base as NSString).appendingPathComponent(trimmedName)
    }
    private var canCreate: Bool {
        !trimmedName.isEmpty &&
        !folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Novo Projeto").font(.title2).bold()
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

            Form {
                Section("Identificação") {
                    TextField("Nome do projeto", text: $name, prompt: Text("meu-projeto"))

                    HStack {
                        TextField("Pasta do projeto", text: $folderPath,
                                  prompt: Text(derivedPath.isEmpty
                                               ? "/Users/você/DEV/meu-projeto" : derivedPath))
                            .font(.system(.body, design: .monospaced))
                        Button("Escolher…") { chooseParentFolder() }
                    }
                    Text("Composta a partir da pasta padrão + nome — pode ajustar aqui. A pasta padrão fica em Ajustes › Projetos.")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("Pasta (grupo)", selection: $group) {
                        Text("Sem pasta").tag(String?.none)
                        ForEach(store.groupNames, id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                        Divider()
                        Text("Nova pasta…").tag(Optional(Self.newGroupSentinel))
                    }
                    if group == Self.newGroupSentinel {
                        TextField("Nome da nova pasta", text: $newGroupName, prompt: Text("Clientes"))
                    }
                }

                Section("CLI") {
                    CLIConfigSection(project: $draft)
                }

                Section("Terminal") {
                    Picker("Estilo", selection: $layout) {
                        ForEach(SoloTerminalLayout.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(layout == .fullscreen
                         ? "Tela cheia nativa no monitor escolhido — cria a própria mesa."
                         : "O terminal preenche o monitor escolhido (nova mesa).")
                        .font(.caption).foregroundStyle(.secondary)

                    if displays.count > 1 {
                        Picker("Monitor", selection: $selectedDisplayID) {
                            ForEach(displays) { d in
                                Text(d.name + (d.isMain ? " (Principal)" : "")).tag(d.id)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Criar") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
            .padding(16)
        }
        .frame(width: 540, height: 560)
        .onAppear { if folderPath.isEmpty { folderPath = derivedPath } }
        .onChange(of: name) { _, _ in
            if !pathEdited { folderPath = derivedPath }
        }
        .onChange(of: folderPath) { _, new in
            if new != derivedPath { pathEdited = true }
        }
    }

    /// The group actually used — resolving the "nova pasta" placeholder.
    private var resolvedGroup: String? {
        guard let group else { return nil }
        if group == Self.newGroupSentinel {
            let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return group.isEmpty ? nil : group
    }

    private func create() {
        guard canCreate,
              let display = displays.first(where: { $0.id == selectedDisplayID })
                ?? DisplayManager.main()
        else { return }
        onCreate(trimmedName, folderPath.trimmingCharacters(in: .whitespacesAndNewlines),
                 draft, layout, resolvedGroup, display)
        dismiss()
    }

    /// Pick a parent folder for THIS project; the name keeps being appended.
    private func chooseParentFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        if !base.isEmpty { panel.directoryURL = URL(fileURLWithPath: base) }
        if panel.runModal() == .OK, let url = panel.url {
            baseOverride = url.path
            pathEdited = false
            folderPath = trimmedName.isEmpty
                ? url.path : (url.path as NSString).appendingPathComponent(trimmedName)
        }
    }
}
