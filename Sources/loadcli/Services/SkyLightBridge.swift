import Foundation

/// Read-only access to the private SkyLight Space APIs.
///
/// We do NOT create/switch Spaces with these (that is unreliable from a normal
/// process on modern macOS — it is why yabai needs SIP disabled). We only READ
/// the current Space layout to *verify* that the Mission Control automation in
/// `SpaceManager` actually created a new desktop, and on which display.
enum SkyLight {
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias CopyDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias GetActiveSpaceFn = @convention(c) (Int32) -> UInt64

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        guard let h = handle, let s = dlsym(h, name) else { return nil }
        return unsafeBitCast(s, to: T.self)
    }

    private static let mainConnFn = sym("SLSMainConnectionID", MainConnFn.self)
    private static let copyDisplaySpacesFn = sym("SLSCopyManagedDisplaySpaces", CopyDisplaySpacesFn.self)
    private static let getActiveSpaceFn = sym("SLSGetActiveSpace", GetActiveSpaceFn.self)

    static var isAvailable: Bool { mainConnFn != nil && copyDisplaySpacesFn != nil }

    static var connection: Int32 { mainConnFn?() ?? 0 }

    static func activeSpace() -> UInt64 { getActiveSpaceFn?(connection) ?? 0 }

    /// Map of display UUID string -> number of (non-fullscreen) desktops on it.
    static func desktopCountsByDisplay() -> [String: Int] {
        guard let arr = copyDisplaySpacesFn?(connection)?.takeRetainedValue()
                as? [[String: Any]] else { return [:] }
        var result: [String: Int] = [:]
        for disp in arr {
            guard let uuid = disp["Display Identifier"] as? String else { continue }
            let spaces = (disp["Spaces"] as? [[String: Any]]) ?? []
            // type 0 == user desktop; type 4 == fullscreen. Count desktops only.
            let desktops = spaces.filter { (($0["type"] as? Int) ?? 0) == 0 }
            result[uuid] = desktops.count
        }
        return result
    }

    static func totalDesktopCount() -> Int {
        desktopCountsByDisplay().values.reduce(0, +)
    }
}
