import AppKit
import ApplicationServices

/// Creates and switches to a new macOS desktop ("mesa") on a chosen display by
/// driving Mission Control through the Accessibility API.
///
/// Why this approach: creating a *usable* Space via the private SkyLight API is
/// unreliable from a normal process on modern macOS (it is why yabai requires
/// SIP to be disabled). Mission Control's "+" button is the supported,
/// SIP-free path. We detect the button locale-independently (a button in the
/// spaces bar with an empty title) and target the right monitor by the button's
/// on-screen position. `SkyLight` (read-only) verifies a desktop was created.
@MainActor
enum SpaceManager {
    private static func dockApp() -> AXUIElement? {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        return AX.app(pid: dock.processIdentifier)
    }

    static func openMissionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.open(url)
    }

    static func pressEscape() {
        let src = CGEventSource(stateID: .combinedSessionState)
        CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }

    /// All Mission Control "add desktop" buttons (one per display) with positions.
    private static func currentAddButtons() -> [(el: AXUIElement, pos: CGPoint)] {
        guard let dock = dockApp() else { return [] }
        var result: [(AXUIElement, CGPoint)] = []
        for el in AX.descendants(dock) {
            guard AX.role(el) == (kAXButtonRole as String) else { continue }
            let title = AX.title(el) ?? ""
            let desc = AX.desc(el) ?? ""
            if title.isEmpty && !desc.isEmpty, let p = AX.position(el) {
                result.append((el, p))
            }
        }
        return result
    }

    /// Titles of the desktop/space buttons sharing the same spaces bar as `addButton`.
    private static func spaceTitles(forBarOf addButton: AXUIElement) -> [String] {
        guard let bar = AX.parent(addButton) else { return [] }
        return AX.children(bar)
            .filter { AX.role($0) == (kAXButtonRole as String) }
            .compactMap { AX.title($0) }
            .filter { !$0.isEmpty }
    }

    private static func spaceButton(inBarOf addButton: AXUIElement, title: String) -> AXUIElement? {
        guard let bar = AX.parent(addButton) else { return nil }
        return AX.children(bar).first {
            AX.role($0) == (kAXButtonRole as String) && (AX.title($0) ?? "") == title
        }
    }

    private static func waitForAddButtons(timeout: TimeInterval) async -> [(el: AXUIElement, pos: CGPoint)] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let b = currentAddButtons()
            if !b.isEmpty { return b }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return currentAddButtons()
    }

    private static func targetAddButton(_ buttons: [(el: AXUIElement, pos: CGPoint)],
                                        display: DisplayInfo) -> AXUIElement? {
        buttons.first { DisplayManager.display(containingCGPoint: $0.pos)?.id == display.id }?.el
            ?? buttons.first?.el
    }

    enum Result { case created, createdNoSwitch, failed }

    /// Create a new desktop on `display` and switch to it. Returns the outcome.
    static func createAndEnterDesktop(on display: DisplayInfo) async -> Result {
        let before = SkyLight.desktopCountsByDisplay()[display.id] ?? -1

        openMissionControl()
        let buttons = await waitForAddButtons(timeout: 2.5)
        guard let add = targetAddButton(buttons, display: display) else {
            pressEscape()
            return .failed
        }

        let beforeTitles = Set(spaceTitles(forBarOf: add))
        AX.press(add)
        try? await Task.sleep(nanoseconds: 800_000_000)

        // Re-resolve the spaces bar (the AX tree rebuilds after creating a desktop).
        let buttons2 = currentAddButtons()
        let add2 = targetAddButton(buttons2, display: display) ?? add
        let afterTitles = Set(spaceTitles(forBarOf: add2))
        let newTitle = afterTitles.subtracting(beforeTitles).first

        var switched = false
        if let newTitle, let newSpace = spaceButton(inBarOf: add2, title: newTitle) {
            switched = AX.press(newSpace)   // clicking a desktop switches to it and closes MC
            try? await Task.sleep(nanoseconds: 450_000_000)
        }

        // Close Mission Control if it is somehow still open.
        if !currentAddButtons().isEmpty { pressEscape() }
        try? await Task.sleep(nanoseconds: 250_000_000)

        let after = SkyLight.desktopCountsByDisplay()[display.id] ?? -1
        let created = (after > before) || (newTitle != nil)
        if created { return switched ? .created : .createdNoSwitch }
        return .failed
    }
}
