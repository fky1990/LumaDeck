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
    private let powerController = DisplayPowerController()
    private var brightnessCache: [CGDirectDisplayID: Double] = [:]
    private var nameCache: [CGDirectDisplayID: String] = [:]
    private var modeCache: [CGDirectDisplayID: [DisplayModeOption]] = [:]
    private var currentModeCache: [CGDirectDisplayID: DisplayModeOption] = [:]
    private var disabledDisplayIDs = Set<CGDirectDisplayID>()
    private var observer: NSObjectProtocol?
    private var modeChangeTask: Task<Void, Never>?
    private let disabledDefaultsKey = "LumaDeck.disabledDisplayIDs"
    private let preferences = UserDefaults(suiteName: "com.lumadeck.app") ?? .standard

    init() {
        let savedValues = preferences.array(forKey: disabledDefaultsKey) ?? []
        disabledDisplayIDs = Set(savedValues.compactMap { value in
            if let number = value as? NSNumber { return CGDirectDisplayID(number.uint32Value) }
            if let string = value as? String, let id = UInt32(string) { return CGDirectDisplayID(id) }
            return nil
        })
        restoreDisplaysFromPreviousRun()
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        modeChangeTask?.cancel()
    }

    func refresh() {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return }
        for id in powerController.connectedDisplayIDs() where !ids.contains(id) { ids.append(id) }
        for id in disabledDisplayIDs where !ids.contains(id) { ids.append(id) }
        let activeIDs = Set(ids.filter { CGDisplayIsActive($0) != 0 })
        blackoutController.reconcile(activeDisplayIDs: activeIDs)

        let screensByID: [CGDirectDisplayID: NSScreen] = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (CGDirectDisplayID(number.uint32Value), screen)
        })

        displays = ids.map { id in
            let discoveredModes = availableModes(for: id)
            let modes = discoveredModes.isEmpty ? (modeCache[id] ?? []) : discoveredModes
            if !discoveredModes.isEmpty { modeCache[id] = discoveredModes }
            let currentCGMode = CGDisplayCopyDisplayMode(id)
            let current = currentCGMode.flatMap { selected in modes.first(where: { $0.mode.ioDisplayModeID == selected.ioDisplayModeID }) }
                ?? currentCGMode.map(makeMode)
                ?? currentModeCache[id]
            if let current { currentModeCache[id] = current }
            let hardwareBrightness = brightnessController.getBrightness(displayID: id).map(Double.init)
            let brightness = brightnessCache[id] ?? hardwareBrightness ?? 1
            let resolvedName = screensByID[id]?.localizedName
                ?? nameCache[id]
                ?? (CGDisplayIsBuiltin(id) != 0 ? "内建显示屏" : "显示器 \(id)")
            nameCache[id] = resolvedName
            let isActive = activeIDs.contains(id)

            return DisplayDevice(
                id: id,
                name: resolvedName,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                brightness: brightness,
                isBlackout: !isActive || blackoutController.isBlackout(displayID: id),
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

        // Prefer removing the display from the active desktop. macOS then moves
        // windows, Dock and the pointer exactly as if the screen were unplugged.
        if powerController.setEnabled(!enabled, displayID: displayID) {
            if enabled { disabledDisplayIDs.insert(displayID) }
            else { disabledDisplayIDs.remove(displayID) }
            saveDisabledDisplayIDs()
            blackoutController.setBlackout(false, displayID: displayID)
            if let index = displays.firstIndex(where: { $0.id == displayID }) {
                displays[index].isBlackout = enabled
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                self?.refresh()
            }
            return
        }

        // Older or restricted systems retain the existing safe visual fallback.
        blackoutController.setBlackout(enabled, displayID: displayID)
        if let index = displays.firstIndex(where: { $0.id == displayID }) {
            displays[index].isBlackout = enabled
        }

    }

    func applyMode(_ option: DisplayModeOption, to displayID: CGDirectDisplayID) {
        let previousMainDisplayID = CGMainDisplayID()
        let result = CGDisplaySetDisplayMode(displayID, option.mode, nil)
        if result == .success {
            // A mode switch emits several screen-parameter notifications. Wait
            // for the final layout before restoring the primary-display policy.
            modeChangeTask?.cancel()
            modeChangeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, let self else { return }
                if CGDisplayIsActive(previousMainDisplayID) != 0,
                   CGMainDisplayID() != previousMainDisplayID {
                    self.makePrimary(previousMainDisplayID)
                } else {
                    self.refresh()
                }
            }
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

        for display in displays where CGDisplayIsActive(display.id) != 0 {
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
        CGDisplayIsActive(displayID) != 0 && CGDisplayBounds(displayID).origin == .zero
    }

    func quitAfterRestoringDisplays() {
        for id in disabledDisplayIDs {
            _ = powerController.setEnabled(true, displayID: id)
        }
        disabledDisplayIDs.removeAll()
        saveDisabledDisplayIDs()
        NSApplication.shared.terminate(nil)
    }

    private func restoreDisplaysFromPreviousRun() {
        guard !disabledDisplayIDs.isEmpty else { return }
        var restored: [CGDirectDisplayID] = []
        for id in disabledDisplayIDs where powerController.setEnabled(true, displayID: id) {
            restored.append(id)
        }
        disabledDisplayIDs.subtract(restored)
        saveDisabledDisplayIDs()
    }

    private func saveDisabledDisplayIDs() {
        preferences.set(disabledDisplayIDs.map(NSNumber.init(value:)), forKey: disabledDefaultsKey)
        preferences.synchronize()
    }

    private func availableModes(for id: CGDirectDisplayID) -> [DisplayModeOption] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let rawModes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        var seen = Set<String>()
        let usableModes = rawModes
            .map(makeMode)
            .filter { $0.width >= 800 && $0.height >= 600 && seen.insert($0.id).inserted }
        let hiDPIModes = usableModes.filter(\.isHiDPI)
        return (hiDPIModes.isEmpty ? usableModes : hiDPIModes)
            .sorted {
                if $0.width * $0.height != $1.width * $1.height { return $0.width * $0.height < $1.width * $1.height }
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
