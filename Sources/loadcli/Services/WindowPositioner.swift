import AppKit
import ApplicationServices

/// Positions an app's front window into a target rectangle (left/right half).
@MainActor
enum WindowPositioner {
    /// Wait for a freshly launched app's front window and return its AX element.
    static func frontWindow(bundleID: String, timeout: TimeInterval = 5) async -> AXUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first {
                let appEl = AX.app(pid: running.processIdentifier)
                if let focused = AX.focusedWindow(appEl) { return focused }
                if let first = AX.windows(appEl).first { return first }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    /// Left/right target rects (top-left CG/AX coords) for a display + left ratio.
    static func halfRects(for display: DisplayInfo, leftRatio: Double) -> (left: CGRect, right: CGRect) {
        let vf = display.visibleFrame
        let r = max(0.2, min(0.8, leftRatio))
        let leftCocoa = NSRect(x: vf.minX, y: vf.minY, width: vf.width * r, height: vf.height)
        let rightCocoa = NSRect(x: vf.minX + vf.width * r, y: vf.minY,
                                width: vf.width * (1 - r), height: vf.height)
        return (DisplayManager.cocoaToCG(leftCocoa), DisplayManager.cocoaToCG(rightCocoa))
    }

    /// Move + resize a window. Several passes because some apps clamp on first set.
    static func place(_ window: AXUIElement, in rect: CGRect) {
        AX.setPosition(window, rect.origin)
        AX.setSize(window, rect.size)
        AX.setPosition(window, rect.origin)
        AX.setSize(window, rect.size)
    }
}
