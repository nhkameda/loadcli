import SwiftUI

/// One project card.
///
/// A single click selects (Finder-style), a double click starts the project —
/// and there is an explicit "Iniciar" button plus direct shortcuts to the
/// project's folder, website, repository and editor.
struct ProjectCardView: View {
    let project: Project
    var isSelected: Bool = false
    var onSelect: () -> Void = {}
    var onLaunch: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onRevealFolder: () -> Void = {}
    var onOpenWebsite: () -> Void = {}
    var onOpenRepository: () -> Void = {}
    var folders: [ProjectFolder] = []
    var onMove: (String?) -> Void = { _ in }

    @State private var hovering = false
    @State private var confirmingDelete = false

    private var accent: Color { Color(hex: project.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            titleBlock
            Spacer(minLength: 0)
            detailLines
            Divider().opacity(0.5)
            actionBar
        }
        .padding(14)
        .frame(height: 226, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(hovering || isSelected ? 0.12 : 0.05),
                radius: hovering || isSelected ? 8 : 3, y: hovering || isSelected ? 4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // The 2-click gesture is declared first so SwiftUI gives it a chance
        // before falling back to the single click.
        .onTapGesture(count: 2) { onLaunch() }
        .onTapGesture(count: 1) { onSelect() }
        .onHover { hovering = $0 }
        .help("Clique para selecionar · clique duplo para iniciar")
        .contextMenu {
            Button("Iniciar") { onLaunch() }
            Button("Editar…") { onEdit() }
            Divider()
            Button("Abrir pasta no Finder") { onRevealFolder() }
            if project.hasWebsite { Button("Abrir site") { onOpenWebsite() } }
            if project.hasRepo { Button("Abrir repositório") { onOpenRepository() } }
            Divider()
            Button("Duplicar…") { onDuplicate() }
            Menu("Mover para") {
                Button("Sem pasta") { onMove(nil) }
                    .disabled(project.groupName == nil)
                if !folders.isEmpty { Divider() }
                ForEach(folders) { f in
                    Button(f.name.isEmpty ? "Pasta" : f.name) { onMove(f.name) }
                        .disabled(ProjectFolder.matchKey(for: project.groupName ?? "") == f.matchKey)
                }
            }
            Divider()
            Button("Excluir card", role: .destructive) { confirmingDelete = true }
        }
        .alert("Excluir o card “\(project.name)”?", isPresented: $confirmingDelete) {
            Button("Excluir card", role: .destructive) { onDelete() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O arquivo LOADCLI.md vai para o Lixo. A pasta do projeto e os arquivos dentro dela não são tocados.")
        }
    }

    private var borderColor: Color {
        if isSelected { return accent }
        return hovering ? accent.opacity(0.55) : Color.black.opacity(0.08)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.gradient)
                    .frame(width: 42, height: 42)
                Image(systemName: project.iconSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            HStack(spacing: 6) {
                Tag(text: project.cliShortLabel, systemImage: "chevron.right")
                if project.wantsSoloFullscreen {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.secondary)
                        .help("Abre em tela cheia")
                } else if project.createsNewDesktop {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .foregroundStyle(.secondary)
                        .help("Cria uma nova mesa")
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name.isEmpty ? "Sem nome" : project.name)
                .font(.headline)
                .lineLimit(1)
            Label(project.folderName, systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(project.folderPath)
            if !project.trimmedDetails.isEmpty {
                Text(project.trimmedDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            if project.hasRepo {
                Label(project.repoShortLabel, systemImage: project.repoSystemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(project.trimmedRepo)
            }
            secondaryPaneLine
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button { onLaunch() } label: {
                Label("Iniciar", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(accent)
            .help("Iniciar o projeto (ou clique duplo no card)")

            Spacer(minLength: 0)

            iconButton("folder", help: "Abrir a pasta do projeto no Finder",
                       enabled: !project.folderPath.isEmpty, action: onRevealFolder)
            iconButton("globe",
                       help: project.hasWebsite ? "Abrir \(project.trimmedURL)" : "Sem site cadastrado",
                       enabled: project.hasWebsite, action: onOpenWebsite)
            iconButton(project.repoSystemImage,
                       help: project.hasRepo ? "Abrir \(project.repoShortLabel)" : "Sem repositório cadastrado",
                       enabled: project.hasRepo, action: onOpenRepository)
            iconButton("pencil", help: "Editar o card", enabled: true, action: onEdit)
        }
    }

    private func iconButton(_ symbol: String, help: String,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.35))
        .help(help)
    }

    /// The line describing what opens beside the terminal.
    @ViewBuilder private var secondaryPaneLine: some View {
        switch project.secondaryPane {
        case .browser:
            if !project.url.isEmpty {
                Label(project.url, systemImage: "globe")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .finder:
            Label((project.effectiveFinderPath as NSString).lastPathComponent.isEmpty
                    ? "Finder" : (project.effectiveFinderPath as NSString).lastPathComponent,
                  systemImage: "folder.badge.gearshape")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .none:
            Label(project.soloTerminalLayout == .fullscreen ? "Terminal · tela cheia" : "Só terminal",
                  systemImage: project.soloTerminalLayout == .fullscreen
                    ? "arrow.up.left.and.arrow.down.right" : "terminal")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
