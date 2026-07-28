import Foundation

struct AppSettings: Codable, Equatable {
    var alwaysAskMonitor: Bool = true
    var defaultSplitRatio: Double = 0.5
    var launchDelaySeconds: Double = 0.9   // wait before positioning windows

    // After the terminal is focused, mimic the user pressing ⌘+ to bump the
    // font up. `increaseTerminalFont` toggles it; `terminalFontZoomSteps` is
    // how many presses (1–20).
    var increaseTerminalFont: Bool = true
    var terminalFontZoomSteps: Int = 7

    // Parent folder where "Novo Projeto" scaffolds a fresh project folder
    // (`<defaultProjectsFolder>/<name>`). Suggested as ~/DEV; user-editable.
    var defaultProjectsFolder: String = AppSettings.suggestedDevFolder

    // Root folders scanned at launch looking for LOADCLI.md files — this is
    // what makes the cards dynamic across synced machines. Empty on a fresh
    // install; `LegacyMigration` seeds it from the old projects.json.
    var projectRoots: [String] = []
    /// How deep below a root the scan descends before giving up.
    var scanMaxDepth: Int = 6
    /// Re-scan automatically when the app opens (the cache shows up instantly
    /// either way; this only controls the background refresh).
    var scanOnLaunch: Bool = true

    /// Sensible starting suggestion: the real user's `~/DEV` (the app is not
    /// sandboxed, so this resolves to `/Users/<user>/DEV`).
    static var suggestedDevFolder: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("DEV")
    }

    init() {}

    /// Decode tolerantly: settings.json written by older versions won't have
    /// the newer keys, so missing keys fall back to the defaults instead of
    /// failing the whole decode (which would reset every setting).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        alwaysAskMonitor      = try c.decodeIfPresent(Bool.self,   forKey: .alwaysAskMonitor)      ?? d.alwaysAskMonitor
        defaultSplitRatio     = try c.decodeIfPresent(Double.self, forKey: .defaultSplitRatio)     ?? d.defaultSplitRatio
        launchDelaySeconds    = try c.decodeIfPresent(Double.self, forKey: .launchDelaySeconds)    ?? d.launchDelaySeconds
        increaseTerminalFont  = try c.decodeIfPresent(Bool.self,   forKey: .increaseTerminalFont)  ?? d.increaseTerminalFont
        terminalFontZoomSteps = try c.decodeIfPresent(Int.self,    forKey: .terminalFontZoomSteps) ?? d.terminalFontZoomSteps
        // Treat a missing OR empty stored value as "not configured" → suggest ~/DEV.
        let storedFolder = try c.decodeIfPresent(String.self, forKey: .defaultProjectsFolder) ?? ""
        defaultProjectsFolder = storedFolder.isEmpty ? d.defaultProjectsFolder : storedFolder
        projectRoots          = try c.decodeIfPresent([String].self, forKey: .projectRoots) ?? d.projectRoots
        scanMaxDepth          = try c.decodeIfPresent(Int.self,      forKey: .scanMaxDepth) ?? d.scanMaxDepth
        scanOnLaunch          = try c.decodeIfPresent(Bool.self,     forKey: .scanOnLaunch) ?? d.scanOnLaunch
    }

    /// Roots as absolute, tilde-expanded, de-duplicated paths with any nested
    /// entry dropped (scanning `~/DEV` already covers `~/DEV/clientes`).
    var normalizedRoots: [String] { AppSettings.normalize(roots: projectRoots) }

    /// One canonical spelling for a folder path: tilde expanded, symlinks
    /// resolved, no trailing slash. Everything that indexes projects by path
    /// goes through here, so a root and the folders found under it always agree
    /// (macOS resolves `/var` to `/private/var` while enumerating, for example).
    static func canonical(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let resolved = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        let final = resolved.isEmpty ? expanded : resolved
        return final.hasSuffix("/") && final.count > 1 ? String(final.dropLast()) : final
    }

    static func normalize(roots: [String]) -> [String] {
        let expanded = roots
            .map { canonical($0) }
            .filter { !$0.isEmpty }

        var unique: [String] = []
        for path in expanded where !unique.contains(path) { unique.append(path) }

        // Drop anything contained in another entry.
        return unique.filter { candidate in
            !unique.contains { other in
                other != candidate && candidate.hasPrefix(other + "/")
            }
        }
    }
}
