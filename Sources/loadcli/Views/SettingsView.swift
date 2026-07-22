import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var accessibility = Permissions.hasAccessibility()

    var body: some View {
        Form {
            Section("Comportamento") {
                Toggle("Confirmar ao iniciar (monitor, CLI e modelo)", isOn: $store.settings.alwaysAskMonitor)
                VStack(alignment: .leading) {
                    Text("Espera antes de posicionar as janelas: \(String(format: "%.1f", store.settings.launchDelaySeconds))s")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $store.settings.launchDelaySeconds, in: 0.3...2.5, step: 0.1)
                }
            }

            Section("Permissões") {
                HStack {
                    Image(systemName: accessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibility ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text("Acessibilidade").bold()
                        Text("Criar mesas e posicionar janelas.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Abrir") { Permissions.openAccessibilitySettings() }
                    Button("Verificar") { accessibility = Permissions.hasAccessibility() }
                }
                HStack {
                    Image(systemName: "wand.and.rays").foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("Automação").bold()
                        Text("Controlar Terminal e navegador (será pedido no 1º uso).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Abrir") { Permissions.openAutomationSettings() }
                }
            }

            Section("Dados") {
                HStack {
                    Text("Configurações em")
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configFolder])
                    } label: {
                        Label("Revelar no Finder", systemImage: "folder")
                    }
                }
                LabeledContent("Versão", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .onChange(of: store.settings) { _, _ in store.save() }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
