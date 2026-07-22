import SwiftUI

/// Pre-launch confirmation: which monitor, which CLI/model/effort — pre-filled
/// from the project and editable. Changes are saved back to the project by
/// `AppModel.launch`, so the next launch opens with the last configuration.
struct LaunchConfirmView: View {
    @State private var draft: Project
    @State private var selectedDisplayID: String
    var onLaunch: (Project, DisplayInfo) -> Void
    var onCancel: () -> Void

    private let displays: [DisplayInfo]

    init(project: Project,
         onLaunch: @escaping (Project, DisplayInfo) -> Void,
         onCancel: @escaping () -> Void) {
        let all = DisplayManager.displays()
        displays = all
        _draft = State(initialValue: project)
        let preferred = project.monitorPreference.flatMap { id in
            all.first { $0.id == id }
        } ?? all.first { $0.isMain } ?? all.first
        _selectedDisplayID = State(initialValue: preferred?.id ?? "")
        self.onLaunch = onLaunch
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Iniciar “\(draft.name)”").font(.title2).bold()
                Text("Confira o monitor e o CLI — alterações ficam salvas no projeto.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            if displays.count > 1 {
                HStack(spacing: 14) {
                    ForEach(displays) { d in monitorCard(d) }
                }
            }

            Form {
                Section("CLI") {
                    CLIConfigSection(project: $draft)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: draft.cliTool == .custom ? 190 : 230)

            HStack {
                Button("Cancelar", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Iniciar") {
                    if let d = displays.first(where: { $0.id == selectedDisplayID })
                        ?? DisplayManager.main() {
                        onLaunch(draft, d)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 540)
    }

    private func monitorCard(_ d: DisplayInfo) -> some View {
        let selected = d.id == selectedDisplayID
        return Button { selectedDisplayID = d.id } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: draft.colorHex).gradient.opacity(selected ? 0.9 : 0.35))
                        .frame(width: 120, height: 120 * aspect(d))
                    Image(systemName: "display")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 2) {
                    Text(d.name).font(.subheadline).bold().lineLimit(1)
                    Text("\(Int(d.frame.width))×\(Int(d.frame.height))")
                        .font(.caption).foregroundStyle(.secondary)
                    if d.isMain {
                        Text("Principal").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.tint.opacity(0.18), in: Capsule())
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.accentColor : .black.opacity(0.08),
                        lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func aspect(_ d: DisplayInfo) -> CGFloat {
        guard d.frame.width > 0 else { return 0.62 }
        return min(0.9, max(0.45, d.frame.height / d.frame.width))
    }
}
