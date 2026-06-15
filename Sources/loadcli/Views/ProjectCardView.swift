import SwiftUI

struct ProjectCardView: View {
    let project: Project
    var onLaunch: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false
    @State private var confirmingDelete = false

    private var accent: Color { Color(hex: project.colorHex) }

    var body: some View {
        Button(action: onLaunch) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.gradient)
                            .frame(width: 46, height: 46)
                        Image(systemName: project.iconSymbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if project.workspaceMode == .newDesktop {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .foregroundStyle(.secondary)
                            .help("Cria uma nova mesa")
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name.isEmpty ? "Sem nome" : project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Label(project.folderName, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !project.url.isEmpty {
                        Label(project.url, systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Tag(text: project.cliCommand.isEmpty ? "shell" : project.cliCommand, systemImage: "chevron.right")
                    Spacer()
                    if hovering {
                        Button { onEdit() } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("Editar")
                    }
                }
            }
            .padding(14)
            .frame(height: 168, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hovering ? accent.opacity(0.55) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.12 : 0.05),
                    radius: hovering ? 8 : 3, y: hovering ? 4 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Abrir") { onLaunch() }
            Button("Editar…") { onEdit() }
            Button("Duplicar") { onDuplicate() }
            Divider()
            Button("Excluir", role: .destructive) { confirmingDelete = true }
        }
        .alert("Excluir “\(project.name)”?", isPresented: $confirmingDelete) {
            Button("Excluir", role: .destructive) { onDelete() }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

private struct Tag: View {
    let text: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            Text(text).font(.caption2).monospaced()
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
