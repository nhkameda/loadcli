import Foundation

/// Per-machine state that must NOT travel inside `LOADCLI.md`.
///
/// Two things belong here. The chosen monitor is a display UUID — meaningful
/// only on the Mac that has that screen. And the "recentes" history is personal
/// to each machine; writing it into the synced document would also rewrite the
/// file on every launch, which is exactly the kind of churn that makes Drive /
/// ownCloud produce conflict copies.
struct LocalPrefs: Codable, Equatable {
    struct Recent: Codable, Equatable, Hashable {
        var id: UUID
        var date: Date
    }

    /// project id → display UUID.
    var monitorByProject: [String: String] = [:]
    /// Most recently launched first.
    var recents: [Recent] = []

    static let maxRecents = 40

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monitorByProject = try c.decodeIfPresent([String: String].self, forKey: .monitorByProject) ?? [:]
        recents = try c.decodeIfPresent([Recent].self, forKey: .recents) ?? []
    }

    // MARK: Monitor

    func monitor(for id: UUID) -> String? { monitorByProject[id.uuidString] }

    mutating func setMonitor(_ displayID: String?, for id: UUID) {
        if let displayID, !displayID.isEmpty {
            monitorByProject[id.uuidString] = displayID
        } else {
            monitorByProject.removeValue(forKey: id.uuidString)
        }
    }

    // MARK: Recents

    /// Record a launch, moving the project to the top of the history.
    mutating func noteLaunch(of id: UUID, at date: Date = Date()) {
        recents.removeAll { $0.id == id }
        recents.insert(Recent(id: id, date: date), at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
    }

    mutating func forget(_ id: UUID) {
        recents.removeAll { $0.id == id }
        monitorByProject.removeValue(forKey: id.uuidString)
    }

    mutating func clearRecents() { recents.removeAll() }

    /// Ids in "most recent first" order.
    var recentIDs: [UUID] { recents.map(\.id) }

    func launchDate(of id: UUID) -> Date? { recents.first { $0.id == id }?.date }

    // MARK: Persistence

    static func load(from url: URL) -> LocalPrefs {
        guard let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(LocalPrefs.self, from: data)
        else { return LocalPrefs() }
        return prefs
    }

    func save(to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
