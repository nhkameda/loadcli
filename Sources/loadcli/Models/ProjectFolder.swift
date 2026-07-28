import Foundation

/// A named group of project cards.
///
/// Groups are no longer entities the user creates and projects point at: a group
/// exists because one or more `LOADCLI.md` files declare `grupo: <nome>`. What
/// this struct persists is only the group's *style* (icon, colour) plus its
/// position in the list — keyed by the group name, so it stays valid no matter
/// which machine scanned the folders.
///
/// Note: expand/collapse is intentionally NOT persisted — every launch starts
/// with all folders collapsed (tracked in-memory by `AppModel.expandedFolders`).
struct ProjectFolder: Identifiable, Codable, Hashable {
    /// The group name — also the identity used to match projects to it.
    var id: String = ""
    var iconSymbol: String = "folder.fill"
    var colorHex: String = "#64748B"
    /// Ordering in the main list; equal values fall back to alphabetical.
    var sortIndex: Int = 0

    var name: String {
        get { id }
        set { id = newValue }
    }

    init(name: String = "",
         iconSymbol: String = "folder.fill",
         colorHex: String = "#64748B",
         sortIndex: Int = 0) {
        self.id = name
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id, iconSymbol, colorHex, sortIndex
    }

    /// Tolerant decode, so a `folders.json` written by any version still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        iconSymbol = try c.decodeIfPresent(String.self, forKey: .iconSymbol) ?? "folder.fill"
        colorHex   = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#64748B"
        sortIndex  = try c.decodeIfPresent(Int.self,    forKey: .sortIndex) ?? 0
    }

    /// Case-insensitive key used when matching a project's `grupo:` to a style.
    var matchKey: String { ProjectFolder.matchKey(for: id) }

    static func matchKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// SF Symbols offered when creating a folder.
enum FolderIconCatalog {
    static let symbols: [String] = [
        "folder.fill", "briefcase.fill", "person.2.fill", "building.2.fill",
        "cart.fill", "flask.fill", "star.fill", "tray.full.fill",
        "shippingbox.fill", "hammer.fill", "globe", "cube.fill",
    ]
}
