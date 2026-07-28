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

            Section("Pastas de projetos") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("O loadcli percorre estas pastas e suas subpastas procurando arquivos **LOADCLI.md** e monta os cards a partir deles. Se a pasta estiver sincronizada (Google Drive, ownCloud…), os mesmos cards aparecem em todos os seus Macs.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.settings.projectRoots.isEmpty {
                        Text("Nenhuma pasta cadastrada.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(store.settings.projectRoots, id: \.self) { root in
                            rootRow(root)
                        }
                    }

                    HStack {
                        Button { addRoot() } label: {
                            Label("Adicionar pasta…", systemImage: "plus")
                        }
                        Spacer()
                        Button { Task { await store.refresh() } } label: {
                            if store.isScanning {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Escaneando…")
                                }
                            } else {
                                Label("Reescanear agora", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(store.isScanning || store.settings.projectRoots.isEmpty)
                    }
                }

                Stepper(value: $store.settings.scanMaxDepth, in: 1...12) {
                    Text("Profundidade máxima: **\(store.settings.scanMaxDepth)** níveis")
                }
                Toggle("Reescanear ao abrir o loadcli", isOn: $store.settings.scanOnLaunch)
            }

            Section("Novos projetos") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pasta padrão dos projetos")
                        .font(.subheadline)
                    HStack {
                        TextField("Pasta padrão", text: $store.settings.defaultProjectsFolder,
                                  prompt: Text("/Users/você/DEV"))
                            .textFieldStyle(.roundedBorder)
                        Button("Escolher…") { chooseDefaultFolder() }
                    }
                    Text("“Novo Projeto” cria uma subpasta com o nome do projeto aqui dentro, grava o LOADCLI.md e já abre o terminal nela.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Fonte do terminal") {
                Toggle("Aumentar a fonte ao abrir o terminal", isOn: $store.settings.increaseTerminalFont)
                if store.settings.increaseTerminalFont {
                    Stepper(value: $store.settings.terminalFontZoomSteps, in: 1...20) {
                        Text("Aumentos (⌘+): **\(store.settings.terminalFontZoomSteps)×**")
                    }
                    Text("Depois de focar o terminal, o loadcli pressiona ⌘+ essa quantidade de vezes — como você faria à mão. Funciona no Terminal, iTerm e Warp.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    Text("Configurações e cache em")
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([store.configFolder])
                    } label: {
                        Label("Revelar no Finder", systemImage: "folder")
                    }
                }
                LabeledContent("Projetos indexados", value: "\(store.projects.count)")
                LabeledContent("Versão", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 620)
        .onChange(of: store.settings) { _, _ in store.saveSettings() }
    }

    private func rootRow(_ root: String) -> some View {
        let available = store.isRootAvailable(root)
        return HStack(spacing: 8) {
            Image(systemName: available ? "folder.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(available ? Color.accentColor : Color.orange)
                .help(available ? "Disponível" : "Pasta indisponível — os cards em cache são mantidos")
            Text(root)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .help(root)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root)])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .disabled(!available)
            .help("Revelar no Finder")

            Button { store.removeRoot(root) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remover da lista (não apaga nada no disco)")
        }
        .padding(.vertical, 2)
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Adicionar"
        let current = store.settings.projectRoots.first ?? store.settings.defaultProjectsFolder
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current) }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.addRoot(url.path) }
        Task { await store.refresh() }
    }

    private func chooseDefaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        let current = store.settings.defaultProjectsFolder
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current) }
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.defaultProjectsFolder = url.path
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
