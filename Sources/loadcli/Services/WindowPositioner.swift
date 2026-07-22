import AppKit
import ApplicationServices

/// Finds the windows a launch created and places them in the split layout —
/// verifying they actually live on the desktop we created.
@MainActor
enum WindowPositioner {
    /// An AX window plus its stable CGWindowID (when resolvable).
    struct TrackedWindow {
        let element: AXUIElement
        let windowID: CGWindowID?
    }

    /// Current CGWindowIDs of an app's windows (used to detect a newly opened one).
    static func windowIDs(bundleID: String) -> Set<CGWindowID> {
        guard let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first else { return [] }
        let appEl = AX.app(pid: running.processIdentifier)
        return Set(AX.windows(appEl).compactMap { AX.windowID($0) })
    }

    /// Wait for and return the window the app opened that is NOT in `excluding`.
    /// We can't rely on the focused window because we launch without activating
    /// (to avoid auto-swoosh), so the new window may not be frontmost.
    static func newWindow(bundleID: String, excluding: Set<CGWindowID>,
                          timeout: TimeInterval = 8) async -> TrackedWindow? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first {
                let appEl = AX.app(pid: running.processIdentifier)
                for w in AX.windows(appEl) {
                    if let id = AX.windowID(w), !excluding.contains(id) {
                        return TrackedWindow(element: w, windowID: id)
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Fallback: focused or first window.
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            let appEl = AX.app(pid: running.processIdentifier)
            if let w = AX.focusedWindow(appEl) ?? AX.windows(appEl).first {
                return TrackedWindow(element: w, windowID: AX.windowID(w))
            }
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

    /// Raise a window, make it the app's main window and bring the app
    /// forward. Only called at the end of the launch, when the window already
    /// lives on the current mesa — activating earlier would let auto-swoosh
    /// jump to a Space with the app's other windows.
    static func focus(_ window: TrackedWindow, appBundleID: String) {
        AX.perform(window.element, action: kAXRaiseAction as String)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).first?
            .activate(options: [])
    }

    /// Place the window and confirm it ended up on `expectedSpace`.
    ///
    /// Apps open windows wherever their last window frame was — possibly on
    /// ANOTHER display, whose current Space is not the new desktop. Moving the
    /// window into the target display's rect re-assigns it to that display's
    /// current Space, so placing and verifying (with retries) is what
    /// guarantees the window lands on the mesa we created.
    static func placeVerified(_ window: TrackedWindow, in rect: CGRect,
                              expectedSpace: UInt64?) async -> Bool {
        place(window.element, in: rect)
        guard let expectedSpace, let id = window.windowID else { return true }
        for _ in 0..<4 {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if SkyLight.space(ofWindow: id) == expectedSpace { return true }
            place(window.element, in: rect)
        }
        return SkyLight.space(ofWindow: id) == expectedSpace
    }
}
