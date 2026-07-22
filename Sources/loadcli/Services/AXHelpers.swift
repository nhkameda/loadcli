import ApplicationServices
import AppKit

/// Thin wrappers around the Accessibility (AXUIElement) C API.
enum AX {
    static func app(pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

    static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        guard let raw = attribute(el, kAXChildrenAttribute as String) else { return [] }
        return (raw as? [AXUIElement]) ?? []
    }

    static func parent(_ el: AXUIElement) -> AXUIElement? {
        guard let raw = attribute(el, kAXParentAttribute as String) else { return nil }
        return (raw as! AXUIElement)
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        attribute(el, name) as? String
    }

    static func role(_ el: AXUIElement) -> String? { string(el, kAXRoleAttribute as String) }
    static func title(_ el: AXUIElement) -> String? { string(el, kAXTitleAttribute as String) }
    static func desc(_ el: AXUIElement) -> String? { string(el, kAXDescriptionAttribute as String) }
    static func identifier(_ el: AXUIElement) -> String? { string(el, "AXIdentifier") }

    /// Dock-private attribute on Mission Control's `mc.display` groups: the
    /// CGDirectDisplayID of the monitor the group belongs to.
    static func displayID(_ el: AXUIElement) -> CGDirectDisplayID? {
        (attribute(el, "AXDisplayID") as? NSNumber)?.uint32Value
    }

    static func position(_ el: AXUIElement) -> CGPoint? {
        guard let v = attribute(el, kAXPositionAttribute as String) else { return nil }
        var p = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &p)
        return p
    }

    static func size(_ el: AXUIElement) -> CGSize? {
        guard let v = attribute(el, kAXSizeAttribute as String) else { return nil }
        var s = CGSize.zero
        AXValueGetValue(v as! AXValue, .cgSize, &s)
        return s
    }

    @discardableResult
    static func press(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func perform(_ el: AXUIElement, action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }

    @discardableResult
    static func setPosition(_ el: AXUIElement, _ p: CGPoint) -> Bool {
        var point = p
        guard let v = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) == .success
    }

    @discardableResult
    static func setSize(_ el: AXUIElement, _ s: CGSize) -> Bool {
        var sz = s
        guard let v = AXValueCreate(.cgSize, &sz) else { return false }
        return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) == .success
    }

    /// Toggle a window's native full-screen state (`AXFullScreen` — not in the
    /// public headers but honoured by Terminal, iTerm, Warp…). Works without
    /// the window being frontmost. Native full screen makes its own Space on
    /// the display the window currently sits on.
    @discardableResult
    static func setFullscreen(_ el: AXUIElement, _ on: Bool) -> Bool {
        AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString,
                                     on ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }

    static func isFullscreen(_ el: AXUIElement) -> Bool {
        (attribute(el, "AXFullScreen") as? NSNumber)?.boolValue ?? false
    }

    static func windows(_ appEl: AXUIElement) -> [AXUIElement] {
        guard let raw = attribute(appEl, kAXWindowsAttribute as String) else { return [] }
        return (raw as? [AXUIElement]) ?? []
    }

    /// Private `_AXUIElementGetWindow` → the stable CGWindowID for an AX window.
    private static let getWindowFn: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let h = dlopen(nil, RTLD_NOW), let s = dlsym(h, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(s, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    static func windowID(_ window: AXUIElement) -> CGWindowID? {
        guard let fn = getWindowFn else { return nil }
        var id: CGWindowID = 0
        return fn(window, &id) == .success ? id : nil
    }

    static func focusedWindow(_ appEl: AXUIElement) -> AXUIElement? {
        guard let raw = attribute(appEl, kAXFocusedWindowAttribute as String) else { return nil }
        return (raw as! AXUIElement)
    }

    /// Depth-first collect of all descendant elements (bounded for safety).
    static func descendants(_ el: AXUIElement, maxDepth: Int = 12, maxNodes: Int = 4000) -> [AXUIElement] {
        var out: [AXUIElement] = []
        var stack: [(AXUIElement, Int)] = [(el, 0)]
        while let (node, depth) = stack.popLast(), out.count < maxNodes {
            let kids = children(node)
            for k in kids {
                out.append(k)
                if depth + 1 < maxDepth { stack.append((k, depth + 1)) }
            }
        }
        return out
    }
}
