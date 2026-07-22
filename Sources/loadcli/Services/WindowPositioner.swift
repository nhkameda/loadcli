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

    /// Re-apply a window's tiled rect after something resized it out from under
    /// us. Terminal/iTerm keep their column/row count when the font changes, so
    /// a ⌘+ font bump GROWS the window past its half — a couple of delayed
    /// passes snap it back (the app then reflows columns to the smaller width).
    static func reassertRect(_ window: TrackedWindow, in rect: CGRect) async {
        for _ in 0..<3 {
            place(window.element, in: rect)
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    /// Put a window into native macOS full screen (its own Space on whatever
    /// display it currently sits on). Position the window on the target display
    /// first, then call this. Retries because some apps ignore the first set
    /// while a move/resize is still settling.
    @discardableResult
    static func enterFullscreen(_ window: TrackedWindow) -> Bool {
        if AX.isFullscreen(window.element) { return true }
        for _ in 0..<3 {
            if AX.setFullscreen(window.element, true) { return true }
            usleep(120_000)
        }
        return AX.isFullscreen(window.element)
    }

    /// Raise a window and make it its app's main window (no app activation).
    static func raise(_ window: TrackedWindow) {
        AX.perform(window.element, action: kAXRaiseAction as String)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    /// Bring the terminal window to the user's focus, escalating mechanisms
    /// and VERIFYING after each (frontmost app must become the target).
    ///
    /// Why the ladder: after entering the freshly created (empty) mesa,
    /// loadcli is usually no longer the frontmost app, so macOS 14+
    /// cooperative activation (`activate(from:)` — yield) has nothing to
    /// yield and plain `activate(options:)` is ignored. An app may always
    /// activate ITSELF though, so an AppleScript `activate` sent to the
    /// terminal works — and the final fallback is what a human does: click
    /// the window's title bar. Only safe when the window already lives on the
    /// current mesa (no auto-swoosh).
    static func focusVerified(_ window: TrackedWindow, appBundleID: String,
                              appName: String) async -> Bool {
        raise(window)

        func isFront() -> Bool {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == appBundleID
        }
        func settled(_ timeout: TimeInterval) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if isFront() { return true }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            return isFront()
        }
        if isFront() { return true }

        // 1. Cooperative yield — works only while loadcli still holds activation.
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: appBundleID).first {
            app.activate(from: .current, options: [])
            if await settled(0.6) { return true }
        }

        // 2. The target app activates itself via Apple Events.
        _ = AppLauncher.run("tell application \"\(appName)\" to activate")
        if await settled(0.9) { return true }

        // 3. Human-equivalent: click the title bar (cursor restored after).
        if let pos = AX.position(window.element), let size = AX.size(window.element) {
            let original = CGEvent(source: nil)?.location ?? .zero
            let p = CGPoint(x: pos.x + min(size.width / 2, 180), y: pos.y + 12)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(60_000)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 150_000_000)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: original, mouseButton: .left)?.post(tap: .cghidEventTap)
            if await settled(0.9) { return true }
        }
        return isFront()
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
