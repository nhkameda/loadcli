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
    }
}
