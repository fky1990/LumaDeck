import CoreGraphics
import Darwin

final class BrightnessController {
    private static let appleVendorID: UInt32 = 0x0610
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let getter: GetBrightness?
    private let setter: SetBrightness?

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        handle = dlopen(path, RTLD_LAZY)
        if let handle {
            if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
                getter = unsafeBitCast(symbol, to: GetBrightness.self)
            } else { getter = nil }
            if let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
                setter = unsafeBitCast(symbol, to: SetBrightness.self)
            } else { setter = nil }
        } else {
            getter = nil
            setter = nil
        }
    }

    deinit { if let handle { dlclose(handle) } }

    /// DisplayServices is dependable for the built-in panel and Apple displays.
    /// Some third-party monitors return success without changing their backlight,
    /// so those displays deliberately use LumaDeck's visual dimming fallback.
    func supportsReliableHardwareControl(displayID: CGDirectDisplayID) -> Bool {
        guard getter != nil, setter != nil else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
            || CGDisplayVendorNumber(displayID) == Self.appleVendorID
    }

    func getBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard supportsReliableHardwareControl(displayID: displayID), let getter else { return nil }
        var value: Float = 1
        return getter(displayID, &value) == 0 ? value : nil
    }

    @discardableResult
    func setBrightness(_ value: Float, displayID: CGDirectDisplayID) -> Bool {
        guard supportsReliableHardwareControl(displayID: displayID), let setter else { return false }
        return setter(displayID, min(1, max(0, value))) == 0
    }
}
