import Foundation

struct AppSettings: Codable, Equatable {
    var alwaysAskMonitor: Bool = true
    var defaultSplitRatio: Double = 0.5
    var launchDelaySeconds: Double = 0.9   // wait before positioning windows
}
