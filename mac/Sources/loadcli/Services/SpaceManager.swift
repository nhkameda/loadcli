import AppKit
import ApplicationServices

/// Creates and switches to a new macOS desktop ("mesa") on a chosen display.
///
/// **Create** — drive Mission Control's "+" button through the Accessibility
/// API. The Dock exposes a stable identifier tree while Mission Control is
/// open (`mc` → `mc.display` [with `AXDisplayID`] → `mc.spaces` →
/// `mc.spaces.add` / `mc.spaces.list`) — the same path Hammerspoon's
/// `hs.spaces` uses. Creation is confirmed by a new space id appearing for
/// that display in SkyLight's read API, never by counting or names.
///
/// **Switch** — `SLSManagedDisplaySetCurrentSpace`, verified by re-reading the
/// display's current space. On macOS 26, `AXPress` on a desktop thumbnail is
/// accepted but ignored, so the private call is the primary mechanism; the
/// fallback is a synthetic mouse click on the thumbnail (with the spaces bar
/// hover-expanded so its buttons have real on-screen coordinates).
@MainActor
enum SpaceManager {
    enum Result: Equatable {
        case created(spaceID: UInt64)
        case createdNoSwitch(spaceID: UInt64)
        case failed
    }

    /// Set LOADCLI_DEBUG=1 to trace each step on stderr (support/diagnóstico).
    private static let debugEnabled = ProcessInfo.processInfo.environment["LOADCLI_DEBUG"] == "1"
    private static func dlog(_ msg: @autoclosure () -> String) {
        if debugEnabled { FileHandle.standardError.write(Data(("[SpaceManager] " + msg() + "\n").utf8)) }
    }

    // MARK: - Mission Control open/close

    /// `CoreDockSendNotification("com.apple.expose.awake")` toggles Mission
    /// Control exactly like the dedicated key — the mechanism Hammerspoon uses.
    private typealias CoreDockNotifyFn = @convention(c) (CFString, Int32) -> Void
    private static let coreDockNotify: CoreDockNotifyFn? = {
        for handle in [dlopen(nil, RTLD_NOW),
                       dlopen("/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock", RTLD_NOW)] {
            if let h = handle, let s = dlsym(h, "CoreDockSendNotification") {
                return unsafeBitCast(s, to: CoreDockNotifyFn.self)
            }
        }
        return nil
    }()

    /// Under the Hardened Runtime (how the app ships) the CoreDock
    /// notification is silently ignored, so after it fails once we go straight
    /// to the `/usr/bin/open` child, which is proven to work there.
    /// (NSWorkspace with `activates=false` must NOT be used for the
    /// exposelauncher: it wedges the LaunchServices request and the subsequent
    /// `open -b` becomes a no-op — observed on macOS 26.3.)
    private static var coreDockToggleWorks = true

    private static func toggleViaCoreDock() -> Bool {
        guard coreDockToggleWorks, let coreDockNotify else { return false }
        coreDockNotify("com.apple.expose.awake" as CFString, 0)
        return true
    }

    private static func toggleViaOpenTool() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-b", "com.apple.exposelauncher"]
        try? p.run()
    }

    private static func dockApp() -> AXUIElement? {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        return AX.app(pid: dock.processIdentifier)
    }

    /// The Dock's `mc` group — present only while Mission Control is shown.
    private static func missionControlGroup() -> AXUIElement? {
        guard let dock = dockApp() else { return nil }
        return AX.children(dock).first { AX.identifier($0) == "mc" }
    }

    /// Open Mission Control and wait for the Dock's `mc` group to appear.
    private static func openMissionControl() async -> Bool {
        if missionControlGroup() != nil { return true }
        if toggleViaCoreDock() {
            if await poll(1.2, { missionControlGroup() != nil }) { return true }
            coreDockToggleWorks = false
            dlog("CoreDock toggle sem efeito; usando /usr/bin/open daqui em diante")
        }
        toggleViaOpenTool()
        return await poll(2.5) { missionControlGroup() != nil }
    }

    private static func closeMissionControl() async {
        guard missionControlGroup() != nil else { return }
        if toggleViaCoreDock() {
            if await poll(1.2, { missionControlGroup() == nil }) { return }
            coreDockToggleWorks = false
        }
        toggleViaOpenTool()
        if await poll(1.5, { missionControlGroup() == nil }) { return }
        pressEscape()   // last resort — does not always dismiss MC
        _ = await poll(1.0) { missionControlGroup() == nil }
    }

    static func pressEscape() {
        let src = CGEventSource(stateID: .combinedSessionState)
        CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }

    // MARK: - Spaces bar lookup

    private struct SpacesBar {
        let displayID: CGDirectDisplayID?
        let origin: CGPoint
        let addButton: AXUIElement
        let desktopButtons: [AXUIElement]   // bar order == SkyLight desktop order
    }

    private static func spacesBars() -> [SpacesBar] {
        guard let mc = missionControlGroup() else { return [] }
        var bars: [SpacesBar] = []
        for disp in AX.children(mc) where AX.identifier(disp) == "mc.display" {
            var add: AXUIElement?
            var desktops: [AXUIElement] = []
            for group in AX.children(disp) where AX.identifier(group) == "mc.spaces" {
                for child in AX.children(group) {
                    switch AX.identifier(child) {
                    case "mc.spaces.add": add = child
                    case "mc.spaces.list": desktops = AX.children(child)
                    default: break
                    }
                }
            }
            if let add {
                bars.append(SpacesBar(displayID: AX.displayID(disp),
                                      origin: AX.position(disp) ?? .zero,
                                      addButton: add, desktopButtons: desktops))
            }
        }
        return bars
    }

    private static func spacesBar(for display: DisplayInfo) -> SpacesBar? {
        let bars = spacesBars()
        if let exact = bars.first(where: { $0.displayID == display.displayID }) { return exact }
        // Fallback for macOS versions without AXDisplayID: the `mc.display`
        // group's origin coincides with the display's top-left CG corner.
        let target = DisplayManager.cocoaToCG(display.frame).origin
        return bars.min { a, b in
            func d(_ p: CGPoint) -> CGFloat {
                let dx = p.x - target.x, dy = p.y - target.y
                return dx * dx + dy * dy
            }
            return d(a.origin) < d(b.origin)
        }
    }

    private static func waitForSpacesBar(_ display: DisplayInfo,
                                         timeout: TimeInterval) async -> SpacesBar? {
        var found: SpacesBar?
        _ = await poll(timeout) {
            found = spacesBar(for: display)
            return found != nil
        }
        return found
    }

    // MARK: - Public flow

    /// Create a new desktop on `display` and switch to it.
    static func createAndEnterDesktop(on display: DisplayInfo) async -> Result {
        let beforeIDs = Set(SkyLight.desktopIDs(onDisplay: display.id))
        dlog("before: \(beforeIDs.sorted()) display=\(display.displayID) coreDockNotify=\(coreDockNotify != nil)")

        let opened = await openMissionControl()
        dlog("openMissionControl -> \(opened), mcGroup=\(missionControlGroup() != nil), bars=\(spacesBars().count)")
        guard opened, var bar = await waitForSpacesBar(display, timeout: 2.0) else {
            dlog("bar for display not found; bars displayIDs=\(spacesBars().map { String(describing: $0.displayID) })")
            await closeMissionControl()
            return .failed
        }
        // Let Mission Control finish materializing its AX elements before
        // pressing anything (Hammerspoon's MCwaitTime; presses fired too early
        // return success without effect).
        try? await Task.sleep(nanoseconds: 350_000_000)

        var pressed = AX.press(bar.addButton)
        if !pressed {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let fresh = spacesBar(for: display) {
                bar = fresh
                pressed = AX.press(bar.addButton)
            }
        }
        dlog("press add -> \(pressed)")
        guard pressed else {
            await closeMissionControl()
            return .failed
        }

        // The desktop exists once SkyLight reports an id we hadn't seen.
        var newID: UInt64 = 0
        let created = await poll(3.0) {
            if let n = SkyLight.desktopIDs(onDisplay: display.id)
                .first(where: { !beforeIDs.contains($0) }) {
                newID = n
                return true
            }
            return false
        }
        dlog("created=\(created) newID=\(newID)")
        guard created else {
            await closeMissionControl()
            return .failed
        }

        // PRIMARY switch: a real click on the new desktop's thumbnail (Mission
        // Control is still open from the creation step). Only a Dock-driven
        // transition repaints correctly — switching with the SLS call alone
        // leaves the compositor with both desktops (and both menu bars)
        // overlaid until the next real space transition. The click also gives
        // the target display keyboard focus, right where the terminal opens.
        if await clickThumbnail(of: newID, display: display) {
            return .created(spaceID: newID)
        }
        dlog("clique no thumbnail falhou; tentando troca via SLS")
        await closeMissionControl()
        if await slsSwitch(to: newID, display: display) {
            return .created(spaceID: newID)
        }
        dlog("switch to \(newID) failed (click + SLS)")
        return .createdNoSwitch(spaceID: newID)
    }

    /// Switch `display` to one of its existing desktops, verified.
    /// SLS-first (fast, no UI) — used by programmatic paths like the doctor's
    /// restore; project launches switch via the thumbnail click instead.
    static func switchTo(spaceID: UInt64, display: DisplayInfo) async -> Bool {
        guard SkyLight.desktopIDs(onDisplay: display.id).contains(spaceID) else { return false }
        if await slsSwitch(to: spaceID, display: display) { return true }
        return await clickThumbnail(of: spaceID, display: display)
    }

    private static func slsSwitch(to spaceID: UInt64, display: DisplayInfo) async -> Bool {
        for _ in 0..<2 {
            SkyLight.requestSwitch(to: spaceID, onDisplay: display.id)
            if await poll(1.2, { SkyLight.currentSpace(onDisplay: display.id) == spaceID }) {
                return true
            }
        }
        return false
    }

    /// Remove a desktop via the thumbnail's `AXRemoveDesktop` action (used by
    /// the `--doctor` self-test). Timing-sensitive: needs a settle delay after
    /// Mission Control opens, so it retries.
    static func removeDesktop(spaceID: UInt64, display: DisplayInfo) async -> Bool {
        for _ in 0..<3 {
            if !SkyLight.desktopIDs(onDisplay: display.id).contains(spaceID) { break }
            guard await openMissionControl() else { continue }
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let idx = SkyLight.desktopIDs(onDisplay: display.id).firstIndex(of: spaceID),
               let bar = spacesBar(for: display), bar.desktopButtons.indices.contains(idx) {
                AX.perform(bar.desktopButtons[idx], action: "AXRemoveDesktop")
                if await poll(2.5, { !SkyLight.desktopIDs(onDisplay: display.id).contains(spaceID) }) {
                    await closeMissionControl()
                    return true
                }
            }
            await closeMissionControl()
        }
        return !SkyLight.desktopIDs(onDisplay: display.id).contains(spaceID)
    }

    // MARK: - Thumbnail-click fallback

    /// Human-equivalent switch: hover the top edge so the collapsed spaces bar
    /// expands (thumbnails only get real on-screen coordinates then), click the
    /// desktop's thumbnail, restore the cursor.
    private static func clickThumbnail(of spaceID: UInt64, display: DisplayInfo) async -> Bool {
        guard await openMissionControl() else { return false }
        try? await Task.sleep(nanoseconds: 600_000_000)

        let originalMouse = CGEvent(source: nil)?.location ?? .zero
        defer { postMouseMove(originalMouse) }

        let frame = DisplayManager.cocoaToCG(display.frame)
        for i in 0...8 {
            postMouseMove(CGPoint(x: frame.midX + CGFloat(i * 2), y: frame.minY + 6))
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        try? await Task.sleep(nanoseconds: 800_000_000)   // expansion animation

        guard let idx = SkyLight.desktopIDs(onDisplay: display.id).firstIndex(of: spaceID),
              let bar = spacesBar(for: display), bar.desktopButtons.indices.contains(idx),
              let pos = AX.position(bar.desktopButtons[idx]),
              let size = AX.size(bar.desktopButtons[idx]) else {
            await closeMissionControl()
            return false
        }
        postMouseClick(CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2))
        try? await Task.sleep(nanoseconds: 150_000_000)
        postMouseMove(originalMouse)   // snappy restore; defer re-posts harmlessly
        let switched = await poll(3.0) { SkyLight.currentSpace(onDisplay: display.id) == spaceID }
        await closeMissionControl()   // the click normally closes MC; make sure
        return switched
    }

    private static func postMouseMove(_ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func postMouseClick(_ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    // MARK: -

    private static func poll(_ timeout: TimeInterval,
                             _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }
}
