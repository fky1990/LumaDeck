import CoreGraphics
import Darwin

final class BrightnessController {
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

    func getBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard let getter else { return nil }
        var value: Float = 1
        return getter(displayID, &value) == 0 ? value : nil
    }

    @discardableResult
    func setBrightness(_ value: Float, displayID: CGDirectDisplayID) -> Bool {
        guard let setter else { return false }
        return setter(displayID, min(1, max(0, value))) == 0
    }
}
