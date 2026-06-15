import SwiftUI

struct MonitorPickerView: View {
    let project: Project
    var onPick: (DisplayInfo) -> Void
    var onCancel: () -> Void

    private var displays: [DisplayInfo] { DisplayManager.displays() }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Em qual monitor?").font(.title2).bold()
                Text("Escolha onde criar a mesa para “\(project.name)”.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ForEach(displays) { d in
                    Button { onPick(d) } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: project.colorHex).gradient.opacity(0.9))
                                    .frame(width: 150, height: 150 * aspect(d))
                                Image(systemName: "display")
                                    .font(.system(size: 34))
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
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Cancelar", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(minWidth: 420)
    }

    private func aspect(_ d: DisplayInfo) -> CGFloat {
        guard d.frame.width > 0 else { return 0.62 }
        return min(0.9, max(0.45, d.frame.height / d.frame.width))
    }
}
