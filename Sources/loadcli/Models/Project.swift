import Foundation

/// How the workspace "mesa" is created when a project is launched.
enum WorkspaceMode: String, Codable, CaseIterable, Identifiable {
    case newDesktop    // create a brand-new Mission Control desktop on the chosen monitor
    case splitCurrent  // arrange split on the chosen monitor, current desktop

    var id: String { rawValue }
    var label: String {
        switch self {
        case .newDesktop:   return "Criar nova mesa (Mission Control)"
        case .splitCurrent: return "Usar a mesa atual"
        }
    }
}

/// Which side each app takes in the split layout.
enum SplitSide: String, Codable, CaseIterable, Identifiable {
    case terminalRight  // Terminal à direita, navegador à esquerda (padrão pedido)
    case terminalLeft

    var id: String { rawValue }
    var label: String {
        switch self {
        case .terminalRight: return "Terminal à direita · painel à esquerda"
        case .terminalLeft:  return "Terminal à esquerda · painel à direita"
        }
    }
}

/// What opens beside the terminal in the split — nothing, a browser at the
/// deploy URL, or a Finder window at a chosen folder.
enum SecondaryPane: String, Codable, CaseIterable, Identifiable {
    case none, browser, finder

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:    return "Nenhum (só terminal)"
        case .browser: return "Navegador"
        case .finder:  return "Finder (pasta)"
        }
    }
    var shortLabel: String {
        switch self {
        case .none:    return "Só terminal"
        case .browser: return "Navegador"
        case .finder:  return "Finder"
        }
    }
    var systemImage: String {
        switch self {
        case .none:    return "rectangle"
        case .browser: return "globe"
        case .finder:  return "folder"
        }
    }
}

/// How a terminal-only project fills the chosen monitor.
enum SoloTerminalLayout: String, Codable, CaseIterable, Identifiable {
    case maximized   // fills the monitor's visible frame (a normal window)
    case fullscreen  // native macOS full screen — its own Space on that monitor

    var id: String { rawValue }
    var label: String {
        switch self {
        case .maximized:  return "Maximizado (preenche o monitor)"
        case .fullscreen: return "Tela cheia (fullscreen nativo)"
        }
    }
    var shortLabel: String {
        switch self {
        case .maximized:  return "Maximizado"
        case .fullscreen: return "Tela cheia"
        }
    }
}

/// Which CLI the terminal runs inside the workspace.
enum CLITool: String, Codable, CaseIterable, Identifiable {
    case claude, codex, custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex:  return "Codex"
        case .custom: return "Comando personalizado"
        }
    }
}

/// Model/effort choices offered per CLI. An empty selection means "padrão"
/// (no flag — the CLI uses its own configuration). Values verified against
/// the installed CLIs: `claude --model/--effort` aliases and Codex's
/// `-m` + `-c model_reasoning_effort=…`.
enum CLICatalog {
    static let claudeModels = ["fable", "opus", "sonnet", "haiku"]
    static let claudeEfforts = ["low", "medium", "high", "xhigh", "max", "ultracode"]
    static let codexModels = ["gpt-5.6-sol", "gpt-5.5"]
    static let codexEfforts = ["minimal", "low", "medium", "high"]

    static func models(for tool: CLITool) -> [String] {
        switch tool {
        case .claude: return claudeModels
        case .codex:  return codexModels
        case .custom: return []
        }
    }

    static func efforts(for tool: CLITool) -> [String] {
        switch tool {
        case .claude: return claudeEfforts
        case .codex:  return codexEfforts
        case .custom: return []
        }
    }
}

/// A configurable development project.
///
/// The source of truth for a project is the `LOADCLI.md` file living inside its
/// own folder (see `ProjectDoc`) — this struct is what the app builds from it,
/// and what the on-disk index cache stores between launches. `folderPath` is
/// therefore never read from the document: it is always the directory where the
/// document was found, so a synced folder works on any Mac.
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var folderPath: String = ""
    var cliCommand: String = "claude"
    var url: String = ""
    var browserBundleID: String = "com.google.Chrome"
    var browserName: String = "Google Chrome"
    var terminalApp: String = "Terminal"
    var workspaceMode: WorkspaceMode = .newDesktop
    var splitSide: SplitSide = .terminalRight
    var splitRatio: Double = 0.5          // fraction reserved for the LEFT pane
    var monitorPreference: String? = nil  // display UUID; machine-local (LocalPrefs)
    var iconSymbol: String = "terminal.fill"
    var colorHex: String = "#7C5CFF"

    // Organisation: the group the card belongs to, by NAME (it travels inside
    // the LOADCLI.md, so it survives syncing). nil/"" = ungrouped.
    var group: String? = nil

    // Free-form description (the markdown body of LOADCLI.md) and the project's
    // repository URL — both shown on the card.
    var details: String = ""
    var repoURL: String = ""

    // Secondary pane beside the terminal. Optional so older projects still
    // decode; nil is interpreted from the presence of a saved URL below.
    var secondaryPaneRaw: String? = nil
    var finderPath: String = ""           // folder to reveal when pane == .finder

    // For terminal-only projects: maximize vs native full screen. Optional for
    // backward compat; nil = maximized (the original behaviour).
    var soloTerminalLayoutRaw: String? = nil

    // CLI tool + per-tool model/effort. Optionals so projects saved by older
    // versions (without these keys) still decode; nil/"" model/effort = padrão.
    var cliToolRaw: String? = nil
    var claudeModel: String? = nil
    var claudeEffort: String? = nil
    var codexModel: String? = nil
    var codexEffort: String? = nil

    init() {}

    /// Decode tolerantly (same rationale as `AppSettings`): the index cache is
    /// rewritten by every version of the app, so a missing key must fall back to
    /// the default instead of dropping the whole entry.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Project()
        id                   = try c.decodeIfPresent(UUID.self,          forKey: .id) ?? d.id
        name                 = try c.decodeIfPresent(String.self,        forKey: .name) ?? d.name
        folderPath           = try c.decodeIfPresent(String.self,        forKey: .folderPath) ?? d.folderPath
        cliCommand           = try c.decodeIfPresent(String.self,        forKey: .cliCommand) ?? d.cliCommand
        url                  = try c.decodeIfPresent(String.self,        forKey: .url) ?? d.url
        browserBundleID      = try c.decodeIfPresent(String.self,        forKey: .browserBundleID) ?? d.browserBundleID
        browserName          = try c.decodeIfPresent(String.self,        forKey: .browserName) ?? d.browserName
        terminalApp          = try c.decodeIfPresent(String.self,        forKey: .terminalApp) ?? d.terminalApp
        workspaceMode        = try c.decodeIfPresent(WorkspaceMode.self, forKey: .workspaceMode) ?? d.workspaceMode
        splitSide            = try c.decodeIfPresent(SplitSide.self,     forKey: .splitSide) ?? d.splitSide
        splitRatio           = try c.decodeIfPresent(Double.self,        forKey: .splitRatio) ?? d.splitRatio
        monitorPreference    = try c.decodeIfPresent(String.self,        forKey: .monitorPreference)
        iconSymbol           = try c.decodeIfPresent(String.self,        forKey: .iconSymbol) ?? d.iconSymbol
        colorHex             = try c.decodeIfPresent(String.self,        forKey: .colorHex) ?? d.colorHex
        group                = try c.decodeIfPresent(String.self,        forKey: .group)
        details              = try c.decodeIfPresent(String.self,        forKey: .details) ?? d.details
        repoURL              = try c.decodeIfPresent(String.self,        forKey: .repoURL) ?? d.repoURL
        secondaryPaneRaw     = try c.decodeIfPresent(String.self,        forKey: .secondaryPaneRaw)
        finderPath           = try c.decodeIfPresent(String.self,        forKey: .finderPath) ?? d.finderPath
        soloTerminalLayoutRaw = try c.decodeIfPresent(String.self,       forKey: .soloTerminalLayoutRaw)
        cliToolRaw           = try c.decodeIfPresent(String.self,        forKey: .cliToolRaw)
        claudeModel          = try c.decodeIfPresent(String.self,        forKey: .claudeModel)
        claudeEffort         = try c.decodeIfPresent(String.self,        forKey: .claudeEffort)
        codexModel           = try c.decodeIfPresent(String.self,        forKey: .codexModel)
        codexEffort          = try c.decodeIfPresent(String.self,        forKey: .codexEffort)
    }

    var cliTool: CLITool {
        get {
            if let raw = cliToolRaw, let tool = CLITool(rawValue: raw) { return tool }
            // Legacy projects only have cliCommand — infer the tool from it.
            let cmd = cliCommand.trimmingCharacters(in: .whitespaces)
            if cmd.isEmpty || cmd == "claude" || cmd.hasPrefix("claude ") { return .claude }
            if cmd == "codex" || cmd.hasPrefix("codex ") { return .codex }
            return .custom
        }
        set { cliToolRaw = newValue.rawValue }
    }

    /// The shell command the terminal actually runs, built from the CLI config.
    var effectiveCLICommand: String {
        func value(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            return s
        }
        switch cliTool {
        case .claude:
            var cmd = "claude"
            if let m = value(claudeModel) { cmd += " --model \(m)" }
            if let e = value(claudeEffort) { cmd += " --effort \(e)" }
            return cmd
        case .codex:
            var cmd = "codex"
            if let m = value(codexModel) { cmd += " -m \(m)" }
            if let e = value(codexEffort) { cmd += " -c model_reasoning_effort=\"\(e)\"" }
            return cmd
        case .custom:
            return cliCommand
        }
    }

    /// Which app (if any) sits beside the terminal. Falls back for legacy
    /// projects: a saved deploy URL means the old browser behaviour.
    var secondaryPane: SecondaryPane {
        get {
            if let raw = secondaryPaneRaw, let p = SecondaryPane(rawValue: raw) { return p }
            return url.trimmingCharacters(in: .whitespaces).isEmpty ? .none : .browser
        }
        set { secondaryPaneRaw = newValue.rawValue }
    }

    /// Folder the Finder pane reveals — the explicit path, or the project folder.
    var effectiveFinderPath: String {
        let p = finderPath.trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? folderPath : p
    }

    /// How a terminal-only project fills the monitor (defaults to maximized).
    var soloTerminalLayout: SoloTerminalLayout {
        get { soloTerminalLayoutRaw.flatMap(SoloTerminalLayout.init) ?? .maximized }
        set { soloTerminalLayoutRaw = newValue.rawValue }
    }

    /// True when this project should go native full screen instead of tiling
    /// or maximizing (terminal-only + full-screen style).
    var wantsSoloFullscreen: Bool {
        secondaryPane == .none && soloTerminalLayout == .fullscreen
    }

    /// Whether launching actually creates a new Mission Control mesa. Native
    /// full screen makes its own Space, so no mesa is created in that case.
    var createsNewDesktop: Bool {
        !wantsSoloFullscreen && workspaceMode == .newDesktop
    }

    /// Short descriptor of the CLI for the card tag (tool-aware, not just the
    /// raw command which stays "claude" for tool-based projects).
    var cliShortLabel: String {
        switch cliTool {
        case .claude: return "claude"
        case .codex:  return "codex"
        case .custom: return cliCommand.trimmingCharacters(in: .whitespaces).isEmpty ? "shell" : cliCommand
        }
    }

    var folderName: String {
        (folderPath as NSString).lastPathComponent
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !folderPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Group / description / repository

    /// The group this card belongs to, normalised — `nil` means "sem pasta".
    var groupName: String? {
        guard let g = group?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty else { return nil }
        return g
    }

    var trimmedDetails: String {
        details.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRepo: String {
        repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasWebsite: Bool { !trimmedURL.isEmpty }
    var hasRepo: Bool { !trimmedRepo.isEmpty }

    /// A short, human label for the repository — `owner/repo` when it looks like
    /// a git host, otherwise the raw value.
    var repoShortLabel: String {
        let raw = trimmedRepo
        guard !raw.isEmpty else { return "" }
        var s = raw
        // git@github.com:owner/repo.git → github.com/owner/repo
        if let range = s.range(of: "@"), s.hasPrefix("git@") {
            s = String(s[range.upperBound...]).replacingOccurrences(of: ":", with: "/")
        }
        for prefix in ["https://", "http://", "ssh://", "git://", "www."] {
            if s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let parts = s.split(separator: "/").map(String.init)
        if parts.count >= 3 { return parts.suffix(2).joined(separator: "/") }
        return s
    }

    /// SF Symbol matching the repository host (GitHub gets the code glyph).
    var repoSystemImage: String {
        trimmedRepo.lowercased().contains("github")
            ? "chevron.left.forwardslash.chevron.right"
            : "arrow.triangle.branch"
    }

    /// A browsable https URL for the repository, converting `git@host:owner/repo`
    /// SSH remotes into their web form. `nil` when nothing sensible can be built.
    var repoWebURL: String? {
        var s = trimmedRepo
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("git@") {
            s = String(s.dropFirst(4)).replacingOccurrences(of: ":", with: "/")
            s = "https://" + s
        } else if s.hasPrefix("ssh://git@") {
            s = "https://" + s.dropFirst("ssh://git@".count)
        } else if !s.contains("://") {
            // A bare `github.com/owner/repo`, or a local path.
            if s.hasPrefix("/") || s.hasPrefix("~") { return nil }
            s = "https://" + s
        }
        if s.hasSuffix(".git") { s.removeLast(4) }
        return s
    }

    /// Absolute path of this project's `LOADCLI.md`.
    var documentPath: String {
        (folderPath as NSString).appendingPathComponent(ProjectDoc.fileName)
    }

    /// Everything searchable about the card, lower-cased, for the quick filter.
    var searchHaystack: String {
        [name, groupName ?? "", folderName, folderPath, details, repoURL, url, cliShortLabel]
            .joined(separator: " ")
            .lowercased()
    }
}

/// Catalog of selectable browsers and terminals used by the editor.
enum AppCatalog {
    struct Option: Identifiable, Hashable {
        let id: String          // bundle id
        let name: String        // app name (used in AppleScript / display)
        var label: String { name }
    }

    static let browsers: [Option] = [
        .init(id: "com.google.Chrome", name: "Google Chrome"),
        .init(id: "com.apple.Safari", name: "Safari"),
        .init(id: "com.brave.Browser", name: "Brave Browser"),
        .init(id: "com.microsoft.edgemac", name: "Microsoft Edge"),
        .init(id: "company.thebrowser.Browser", name: "Arc"),
    ]

    static let terminals: [Option] = [
        .init(id: "com.apple.Terminal", name: "Terminal"),
        .init(id: "com.googlecode.iterm2", name: "iTerm"),
        .init(id: "dev.warp.Warp-Stable", name: "Warp"),
    ]

    static func terminalBundleID(forName name: String) -> String {
        terminals.first { $0.name == name }?.id ?? "com.apple.Terminal"
    }
}

/// SF Symbols offered in the editor for visual identity.
enum IconCatalog {
    static let symbols: [String] = [
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "hammer.fill",
        "shippingbox.fill", "globe", "bolt.fill", "cube.fill", "server.rack",
        "cart.fill", "leaf.fill", "flame.fill", "sparkles", "gearshape.fill",
        "chart.bar.fill", "doc.text.fill", "wand.and.stars", "antenna.radiowaves.left.and.right",
        "creditcard.fill", "building.2.fill", "cpu.fill",
    ]
    static let colors: [String] = [
        "#7C5CFF", "#3B82F6", "#06B6D4", "#10B981", "#F59E0B",
        "#EF4444", "#EC4899", "#8B5CF6", "#64748B", "#0EA5E9",
    ]
}
