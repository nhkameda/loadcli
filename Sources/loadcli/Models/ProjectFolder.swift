import Foundation

/// A named group that holds project cards. Projects reference it by `folderID`;
/// deleting a folder just un-groups its projects (never deletes them).
struct ProjectFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var iconSymbol: String = "folder.fill"
    var colorHex: String = "#64748B"
    // Note: expand/collapse is intentionally NOT persisted — every launch starts
    // with all folders collapsed (tracked in-memory by AppModel.expandedFolders).
}

/// SF Symbols offered when creating a folder.
enum FolderIconCatalog {
    static let symbols: [String] = [
        "folder.fill", "briefcase.fill", "person.2.fill", "building.2.fill",
        "cart.fill", "flask.fill", "star.fill", "tray.full.fill",
        "shippingbox.fill", "hammer.fill", "globe", "cube.fill",
    ]
}
