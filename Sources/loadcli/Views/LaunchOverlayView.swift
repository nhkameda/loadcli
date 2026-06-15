import SwiftUI

struct LaunchOverlayView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(model.statusText)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let notice = model.noticeText {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .frame(minWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(radius: 20)
        }
        .transition(.opacity)
    }
}
