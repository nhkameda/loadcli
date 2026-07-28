import Foundation
import CoreGraphics

/// Bridge to the private SkyLight Space APIs.
///
/// READ calls (`SLSCopyManagedDisplaySpaces`, `SLSManagedDisplayGetCurrentSpace`,
/// `SLSCopySpacesForWindows`) enumerate desktops per display and verify results.
///
/// The ONE write call used is `SLSManagedDisplaySetCurrentSpace` — empirically the
/// only reliable way to *switch* desktops on macOS 26: `AXPress` on a Mission
/// Control thumbnail returns success and closes Mission Control but does NOT
/// switch (verified on 26.3). Space *creation* via private APIs remains broken
/// from a normal process (`SLSSpaceCreate` returns an id that never attaches to a
/// display), so creation drives Mission Control's "+" button via Accessibility
/// instead — see `SpaceManager`, which also verifies every switch through the
/// read APIs and falls back to a synthetic thumbnail click if this call ever
/// stops working.
enum SkyLight {
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias CopyDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias GetActiveSpaceFn = @convention(c) (Int32) -> UInt64
    private typealias DisplayCurrentSpaceFn = @convention(c) (Int32, CFString) -> UInt64
    private typealias DisplaySetCurrentSpaceFn = @convention(c) (Int32, CFString, UInt64) -> Int32
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        guard let h = handle, let s = dlsym(h, name) else { return nil }
        return unsafeBitCast(s, to: T.self)
    }

    private static let mainConnFn = sym("SLSMainConnectionID", MainConnFn.self)
    private static let copyDisplaySpacesFn = sym("SLSCopyManagedDisplaySpaces", CopyDisplaySpacesFn.self)
    private static let getActiveSpaceFn = sym("SLSGetActiveSpace", GetActiveSpaceFn.self)
    private static let displayCurrentFn = sym("SLSManagedDisplayGetCurrentSpace", DisplayCurrentSpaceFn.self)
    private static let displaySetCurrentFn = sym("SLSManagedDisplaySetCurrentSpace", DisplaySetCurrentSpaceFn.self)
    private static let spacesForWindowsFn = sym("SLSCopySpacesForWindows", SpacesForWindowsFn.self)

    static var isAvailable: Bool { mainConnFn != nil && copyDisplaySpacesFn != nil }
    static var canSwitch: Bool { displaySetCurrentFn != nil && displayCurrentFn != nil }

    static var connection: Int32 { mainConnFn?() ?? 0 }

    static func activeSpace() -> UInt64 { getActiveSpaceFn?(connection) ?? 0 }

    /// The desktops of one display, in Mission Control order.
    struct DisplaySpaces {
        let uuid: String              // display UUID (matches DisplayInfo.id)
        let currentSpaceID: UInt64
        let desktopIDs: [UInt64]      // type-0 (user desktop) spaces only
    }

    static func displaySpaces() -> [DisplaySpaces] {
        guard let arr = copyDisplaySpacesFn?(connection)?.takeRetainedValue()
                as? [[String: Any]] else { return [] }
        return arr.compactMap { disp in
            guard let uuid = disp["Display Identifier"] as? String else { return nil }
            let spaces = (disp["Spaces"] as? [[String: Any]]) ?? []
            func spaceID(_ s: [String: Any]) -> UInt64 {
                ((s["ManagedSpaceID"] ?? s["id64"]) as? NSNumber)?.uint64Value ?? 0
            }
            let desktops = spaces.filter { (($0["type"] as? Int) ?? 0) == 0 }.map(spaceID)
            let current = (disp["Current Space"] as? [String: Any]).map(spaceID) ?? 0
            return DisplaySpaces(uuid: uuid, currentSpaceID: current, desktopIDs: desktops)
        }
    }

    /// Desktop space ids of a display, in bar order (new desktops are appended).
    static func desktopIDs(onDisplay uuid: String) -> [UInt64] {
        displaySpaces().first { $0.uuid == uuid }?.desktopIDs ?? []
    }

    /// The space currently shown on a display.
    static func currentSpace(onDisplay uuid: String) -> UInt64 {
        displayCurrentFn?(connection, uuid as CFString) ?? 0
    }

    /// Ask the window server to switch a display to one of its spaces.
    /// Fire-and-verify: callers MUST confirm via `currentSpace(onDisplay:)`.
    @discardableResult
    static func requestSwitch(to spaceID: UInt64, onDisplay uuid: String) -> Bool {
        guard let fn = displaySetCurrentFn else { return false }
        return fn(connection, uuid as CFString, spaceID) == 0
    }

    /// The space a window currently lives on (works across displays/spaces).
    static func space(ofWindow windowID: CGWindowID) -> UInt64? {
        guard let fn = spacesForWindowsFn,
              let arr = fn(connection, 0x7, [NSNumber(value: windowID)] as CFArray)?
                  .takeRetainedValue() as? [NSNumber],
              let first = arr.first else { return nil }
        return first.uint64Value
    }
}
