import SwiftUI

/// Create or rename a folder (name, icon, colour). Deleting keeps its projects,
/// just un-grouping them.
struct FolderEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ProjectFolder
    private let isNew: Bool

    init(folder: ProjectFolder?) {
        _draft = State(initialValue: folder ?? ProjectFolder())
        isNew = (folder == nil)
    }

    private var accent: Color { Color(hex: draft.colorHex) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "Nova Pasta" : "Editar Pasta").font(.title2).bold()
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

            Form {
                Section {
                    TextField("Nome", text: $draft.name, prompt: Text("Clientes"))
                    iconRow
                    colorRow
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew {
                    Button("Excluir", role: .destructive) {
                        store.deleteFolder(draft, keepingProjects: true); dismiss()
                    }
                    .help("Remove a pasta; os projetos ficam sem pasta.")
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Criar" : "Salvar") {
                    store.upsertFolder(draft); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460, height: 420)
    }

    private var iconRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ícone").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(FolderIconCatalog.symbols, id: \.self) { sym in
                    Image(systemName: sym)
                        .foregroundStyle(draft.iconSymbol == sym ? accent : .secondary)
                        .frame(width: 30, height: 30)
                        .background(draft.iconSymbol == sym ? accent.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(draft.iconSymbol == sym ? accent : .clear))
                        .onTapGesture { draft.iconSymbol = sym }
                }
            }
        }
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
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
}
