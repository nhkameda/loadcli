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
        case .terminalRight: return "Terminal à direita · navegador à esquerda"
        case .terminalLeft:  return "Terminal à esquerda · navegador à direita"
        }
    }
}

/// A configurable development project.
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
    var monitorPreference: String? = nil  // display UUID; nil = ask / use main
    var iconSymbol: String = "terminal.fill"
    var colorHex: String = "#7C5CFF"

    var folderName: String {
        (folderPath as NSString).lastPathComponent
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !folderPath.trimmingCharacters(in: .whitespaces).isEmpty
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
