import CoreGraphics
import Darwin

/// Runtime wrapper around macOS's display-enabled configuration primitive.
/// It is intentionally resolved dynamically because Apple doesn't publish the
/// symbol in the CoreGraphics Swift module.
final class DisplayPowerController {
    private typealias ConfigureDisplayEnabled = @convention(c) (
        CGDisplayConfigRef?, CGDirectDisplayID, Bool
    ) -> Int32
    private typealias GetDisplayList = @convention(c) (
        UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?
    ) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let configureDisplayEnabled: ConfigureDisplayEnabled?
    private let getDisplayList: GetDisplayList?

    init() {
        let path = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        handle = dlopen(path, RTLD_LAZY)
        if let handle, let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") {
            configureDisplayEnabled = unsafeBitCast(symbol, to: ConfigureDisplayEnabled.self)
        } else {
            configureDisplayEnabled = nil
        }
        if let handle, let symbol = dlsym(handle, "CGSGetDisplayList") {
            getDisplayList = unsafeBitCast(symbol, to: GetDisplayList.self)
        } else {
            getDisplayList = nil
        }
    }

    deinit { if let handle { dlclose(handle) } }

    var isAvailable: Bool { configureDisplayEnabled != nil }

    /// Includes attached displays that CGGetOnlineDisplayList omits after they
    /// have been disabled. Placeholder WindowServer slots are filtered out.
    func connectedDisplayIDs() -> [CGDirectDisplayID] {
        guard let getDisplayList else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        _ = getDisplayList(UInt32(ids.count), &ids, &count)
        return ids.prefix(Int(min(count, UInt32(ids.count)))).filter { id in
            let bounds = CGDisplayBounds(id)
            return CGDisplayIsBuiltin(id) != 0
                || CGDisplayVendorNumber(id) != 0
                || CGDisplayModelNumber(id) != 0
                || bounds.width > 1
                || bounds.height > 1
        }
    }

    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) -> Bool {
        guard let configureDisplayEnabled else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }

        guard configureDisplayEnabled(config, displayID, enabled) == 0 else {
            CGCancelDisplayConfiguration(config)
            return false
        }

        // Enabling at session scope clears a stale disabled base configuration.
        // Disabling remains app-scoped and is also explicitly undone on quit.
        let scope: CGConfigureOption = enabled ? .forSession : .forAppOnly
        return CGCompleteDisplayConfiguration(config, scope) == .success
    }
}
