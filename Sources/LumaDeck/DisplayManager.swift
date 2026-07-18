import AppKit
import Combine
import CoreGraphics

struct DisplayModeOption: Identifiable, Equatable {
    let mode: CGDisplayMode
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double

    var id: String { "\(width)x\(height)-\(pixelWidth)x\(pixelHeight)-\(refreshRate)" }
    var isHiDPI: Bool { pixelWidth > width || pixelHeight > height }
    var resolutionLabel: String { "\(width) × \(height)" }
    var refreshLabel: String { refreshRate > 1 ? String(format: "%.0f Hz", refreshRate) : "系统默认" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct DisplayDevice: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    var brightness: Double
    var isBlackout: Bool
    let modes: [DisplayModeOption]
    var currentMode: DisplayModeOption?

    var currentResolution: String { currentMode?.resolutionLabel ?? "未知" }
    var currentRefreshRate: String { currentMode?.refreshLabel ?? "系统默认" }
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayDevice] = []
    @Published var lastError: String?

    private let brightnessController = BrightnessController()
    private let blackoutController = BlackoutController()
    private var brightnessCache: [CGDirectDisplayID: Double] = [:]
    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return }
        blackoutController.reconcile(activeDisplayIDs: Set(ids))

        let screensByID: [CGDirectDisplayID: NSScreen] = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (CGDirectDisplayID(number.uint32Value), screen)
        })

        displays = ids.map { id in
            let modes = availableModes(for: id)
            let currentCGMode = CGDisplayCopyDisplayMode(id)
            let current = currentCGMode.flatMap { selected in modes.first(where: { $0.mode.ioDisplayModeID == selected.ioDisplayModeID }) }
                ?? currentCGMode.map(makeMode)
            let hardwareBrightness = brightnessController.getBrightness(displayID: id).map(Double.init)
            let brightness = brightnessCache[id] ?? hardwareBrightness ?? 1
            let name = screensByID[id]?.localizedName ?? (CGDisplayIsBuiltin(id) != 0 ? "内建显示屏" : "显示器 \(id)")

            return DisplayDevice(
                id: id,
                name: name,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                brightness: brightness,
                isBlackout: blackoutController.isBlackout(displayID: id),
                modes: modes,
                currentMode: current
            )
        }
    }

    func setBrightness(_ value: Double, for displayID: CGDirectDisplayID) {
        let clamped = min(1, max(0.05, value))
        brightnessCache[displayID] = clamped
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[index].brightness = clamped

        if brightnessController.setBrightness(Float(clamped), displayID: displayID) {
            blackoutController.setDimming(0, displayID: displayID)
        } else {
            // Unsupported displays still get predictable per-screen software dimming.
            blackoutController.setDimming(1 - clamped, displayID: displayID)
        }
    }

    func setBlackout(_ enabled: Bool, for displayID: CGDirectDisplayID) {
        if enabled {
            let visibleCount = displays.filter { !$0.isBlackout }.count
            guard visibleCount > 1 else {
                lastError = "至少需要保留一块可见显示器，以便你随时重新打开其他屏幕。"
                return
            }
        }
        blackoutController.setBlackout(enabled, displayID: displayID)
        if let index = displays.firstIndex(where: { $0.id == displayID }) {
            displays[index].isBlackout = enabled
        }
    }

    func applyMode(_ option: DisplayModeOption, to displayID: CGDirectDisplayID) {
        let result = CGDisplaySetDisplayMode(displayID, option.mode, nil)
        if result == .success {
            refresh()
        } else {
            lastError = "切换显示模式失败（CoreGraphics 错误 \(result.rawValue)）"
        }
    }

    func makePrimary(_ displayID: CGDirectDisplayID) {
        let targetBounds = CGDisplayBounds(displayID)
        guard targetBounds.origin != .zero else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            lastError = "无法开始显示器排列配置。"
            return
        }

        for display in displays {
            let bounds = CGDisplayBounds(display.id)
            let x = Int32(bounds.origin.x - targetBounds.origin.x)
            let y = Int32(bounds.origin.y - targetBounds.origin.y)
            if CGConfigureDisplayOrigin(config, display.id, x, y) != .success {
                CGCancelDisplayConfiguration(config)
                lastError = "设置主显示器失败。"
                return
            }
        }

        let result = CGCompleteDisplayConfiguration(config, .permanently)
        if result == .success { refresh() }
        else { lastError = "保存主显示器设置失败（\(result.rawValue)）。" }
    }

    func isPrimary(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayBounds(displayID).origin == .zero
    }

    private func availableModes(for id: CGDirectDisplayID) -> [DisplayModeOption] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let rawModes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        var seen = Set<String>()
        return rawModes
            .map(makeMode)
            .filter { $0.width >= 800 && $0.height >= 600 && seen.insert($0.id).inserted }
            .sorted {
                if $0.width * $0.height != $1.width * $1.height { return $0.width * $0.height < $1.width * $1.height }
                if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI && !$1.isHiDPI }
                return $0.refreshRate < $1.refreshRate
            }
    }

    private func makeMode(_ mode: CGDisplayMode) -> DisplayModeOption {
        DisplayModeOption(
            mode: mode,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate
        )
    }
}
