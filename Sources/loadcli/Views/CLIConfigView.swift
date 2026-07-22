import SwiftUI

/// CLI + model + effort controls for a project, shared by the editor and the
/// launch-confirmation dialog (both bind to a draft `Project`).
struct CLIConfigSection: View {
    @Binding var project: Project

    var body: some View {
        Picker("CLI", selection: cliToolBinding) {
            ForEach(CLITool.allCases) { Text($0.label).tag($0) }
        }

        switch project.cliTool {
        case .claude:
            OptionOrCustomPicker(title: "Modelo", options: CLICatalog.claudeModels,
                                 value: $project.claudeModel)
            OptionOrCustomPicker(title: "Effort", options: CLICatalog.claudeEfforts,
                                 value: $project.claudeEffort, allowCustom: false)
        case .codex:
            OptionOrCustomPicker(title: "Modelo", options: CLICatalog.codexModels,
                                 value: $project.codexModel)
            OptionOrCustomPicker(title: "Effort", options: CLICatalog.codexEfforts,
                                 value: $project.codexEffort, allowCustom: false)
        case .custom:
            TextField("Comando", text: $project.cliCommand, prompt: Text("claude"))
                .font(.system(.body, design: .monospaced))
        }

        LabeledContent("Comando") {
            Text(project.effectiveCLICommand.isEmpty ? "—" : project.effectiveCLICommand)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var cliToolBinding: Binding<CLITool> {
        Binding(get: { project.cliTool }, set: { project.cliTool = $0 })
    }
}

/// Picker over fixed options plus "Padrão" (empty) and an optional
/// "Personalizado…" free-text entry. `value == nil`/"" means padrão.
struct OptionOrCustomPicker: View {
    let title: String
    let options: [String]
    @Binding var value: String?
    var allowCustom: Bool = true

    private static let customTag = "__custom__"
    @State private var isCustom: Bool

    init(title: String, options: [String], value: Binding<String?>, allowCustom: Bool = true) {
        self.title = title
        self.options = options
        self._value = value
        self.allowCustom = allowCustom
        let v = value.wrappedValue?.trimmingCharacters(in: .whitespaces) ?? ""
        _isCustom = State(initialValue: allowCustom && !v.isEmpty && !options.contains(v))
    }

    var body: some View {
        Picker(title, selection: selection) {
            Text("Padrão").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
            if allowCustom { Text("Personalizado…").tag(Self.customTag) }
        }
        if isCustom {
            TextField("\(title) personalizado", text: customText)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                if isCustom { return Self.customTag }
                let v = value?.trimmingCharacters(in: .whitespaces) ?? ""
                if v.isEmpty { return "" }
                return options.contains(v) ? v : (allowCustom ? Self.customTag : "")
            },
            set: { new in
                if new == Self.customTag {
                    isCustom = true
                } else {
                    isCustom = false
                    value = new.isEmpty ? nil : new
                }
            }
        )
    }

    private var customText: Binding<String> {
        Binding(get: { value ?? "" },
                set: { value = $0.isEmpty ? nil : $0 })
    }
}
