import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: String            // CGDisplay UUID string (stable across launches)
    let displayID: CGDirectDisplayID
    let name: String
    let frame: NSRect         // Cocoa global coords (origin bottom-left)
    let visibleFrame: NSRect  // excludes menu bar / Dock
    let isMain: Bool

    static func == (a: DisplayInfo, b: DisplayInfo) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum DisplayManager {
    static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }

    static func displays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let displayID = CGDirectDisplayID(num.uint32Value)
            let uuid = uuidString(for: displayID) ?? "display-\(displayID)"
            return DisplayInfo(
                id: uuid,
                displayID: displayID,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isMain: screen.frame.origin == .zero
            )
        }
    }

    static func main() -> DisplayInfo? {
        let all = displays()
        return all.first(where: { $0.isMain }) ?? all.first
    }

    static func display(withUUID uuid: String) -> DisplayInfo? {
        displays().first { $0.id == uuid }
    }

    /// Height of the primary (zero-origin) screen, used for Cocoa<->CG flips.
    static func primaryMaxY() -> CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }

    /// Convert a Cocoa (bottom-left origin) rect to a top-left-origin CG/AX rect.
    static func cocoaToCG(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryMaxY() - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Find the display that contains a point given in top-left CG/AX coords.
    /// Falls back to horizontal-range / nearest-center matching (the Mission
    /// Control spaces bar can sit slightly above a display's top edge).
    static func display(containingCGPoint p: CGPoint) -> DisplayInfo? {
        let all = displays()
        if let hit = all.first(where: { cocoaToCG($0.frame).contains(p) }) { return hit }
        if let hit = all.first(where: { r in
            let cg = cocoaToCG(r.frame); return p.x >= cg.minX && p.x <= cg.maxX
        }) { return hit }
        return all.min(by: { a, b in
            let ca = cocoaToCG(a.frame), cb = cocoaToCG(b.frame)
            func d(_ r: CGRect) -> CGFloat {
                let cx = r.midX - p.x, cy = r.midY - p.y; return cx * cx + cy * cy
            }
            return d(ca) < d(cb)
        })
    }
}
