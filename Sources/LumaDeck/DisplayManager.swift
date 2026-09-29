import AppKit
import ColorSync
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
    private struct DisplayContext {
        let profileKey: String
        let legacyProfileKey: String
        let ids: [CGDirectDisplayID]
        let inactiveIDs: Set<CGDirectDisplayID>
        let fingerprints: [CGDirectDisplayID: String]
        let aliases: [CGDirectDisplayID: Set<String>]

        func fingerprint(for id: CGDirectDisplayID) -> String { fingerprints[id]! }
        func matches(_ saved: Set<String>, displayID: CGDirectDisplayID) -> Bool {
            !(aliases[displayID] ?? []).isDisjoint(with: saved)
        }
    }

    @Published private(set) var displays: [DisplayDevice] = []
    @Published var lastError: String?
    @Published var remembersDisplayConfigurations = true {
        didSet {
            preferences.set(remembersDisplayConfigurations, forKey: remembersConfigurationsDefaultsKey)
            if remembersDisplayConfigurations {
                scheduleProfileApplication()
            } else {
                profileTask?.cancel()
            }
        }
    }

    private let brightnessController = BrightnessController()
    private let blackoutController = BlackoutController()
    private let powerController = DisplayPowerController()
    private var brightnessCache: [CGDirectDisplayID: Double] = [:]
    private var nameCache: [CGDirectDisplayID: String] = [:]
    private var modeCache: [CGDirectDisplayID: [DisplayModeOption]] = [:]
    private var currentModeCache: [CGDirectDisplayID: DisplayModeOption] = [:]
    private var disabledDisplayIDs = Set<CGDirectDisplayID>()
    private var observer: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var recoveryTask: Task<Void, Never>?
    private var profileTask: Task<Void, Never>?
    private var recoveryInProgress = false
    private var isPreparingForSleep = false
    private var modeChangeTask: Task<Void, Never>?
    private let disabledDefaultsKey = "LumaDeck.disabledDisplayIDs"
    private let profilesDefaultsKey = "LumaDeck.displayConfigurationProfiles"
    private let remembersConfigurationsDefaultsKey = "LumaDeck.rememberDisplayConfigurations"
    private let preferences = UserDefaults(suiteName: "com.lumadeck.app") ?? .standard

    init() {
        if preferences.object(forKey: remembersConfigurationsDefaultsKey) != nil {
            remembersDisplayConfigurations = preferences.bool(forKey: remembersConfigurationsDefaultsKey)
        }
        let savedValues = preferences.array(forKey: disabledDefaultsKey) ?? []
        disabledDisplayIDs = Set(savedValues.compactMap { value in
            if let number = value as? NSNumber { return CGDirectDisplayID(number.uint32Value) }
            if let string = value as? String, let id = UInt32(string) { return CGDirectDisplayID(id) }
            return nil
        })
        removeStaleDisabledDisplayIDs()
        preserveConfigurationBeforeStartupRestore()
        restoreDisplaysFromPreviousRun()
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDisplayTopologyChange()
            }
        }
        observeSleepAndWake()
        scheduleProfileApplication()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        recoveryTask?.cancel()
        profileTask?.cancel()
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
        setBlackout(enabled, for: displayID, rememberPreference: true)
    }

    private func setBlackout(
        _ enabled: Bool,
        for displayID: CGDirectDisplayID,
        rememberPreference: Bool
    ) {
        let profileContext = rememberPreference
            ? currentDisplayContext().flatMap { $0.ids.contains(displayID) ? $0 : nil }
            : nil
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
            if let profileContext {
                rememberDisplayPreference(enabled, for: displayID, in: profileContext)
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
        var restored: [CGDirectDisplayID] = []
        for id in disabledDisplayIDs where powerController.setEnabled(true, displayID: id) {
            restored.append(id)
        }
        disabledDisplayIDs.subtract(restored)
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

    private func removeStaleDisabledDisplayIDs() {
        guard let activeIDs = activeDisplayIDs() else { return }
        let previousCount = disabledDisplayIDs.count
        disabledDisplayIDs.subtract(activeIDs)
        if disabledDisplayIDs.count != previousCount { saveDisabledDisplayIDs() }
    }

    private func preserveConfigurationBeforeStartupRestore() {
        guard remembersDisplayConfigurations,
              let context = currentDisplayContext(),
              context.ids.contains(where: {
                  CGDisplayIsBuiltin($0) == 0 && CGDisplayIsActive($0) != 0
              }) else { return }
        let actuallyDisabled = context.ids.filter {
            disabledDisplayIDs.contains($0) && CGDisplayIsActive($0) == 0
        }
        guard !actuallyDisabled.isEmpty else { return }

        var profiles = savedDisplayProfiles()
        profiles[context.profileKey] = actuallyDisabled.map(context.fingerprint(for:)).sorted()
        preferences.set(profiles, forKey: profilesDefaultsKey)
    }

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.prepareForSleep()
                }
            })
        }

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.resumeDisplaySession(restoreDisabledDisplays: true)
                }
            })
        }

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeDisplaySession(restoreDisabledDisplays: false) }
        })

        // Unlocking without a full system sleep does not always emit a screen
        // parameter change. Reapply the remembered profile at the unlock event.
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeDisplaySession(restoreDisabledDisplays: false) }
        }
    }

    private func prepareForSleep() {
        // Run before the screen actually sleeps: a queued task can be suspended
        // until after wake, leaving the built-in screen disabled during sleep.
        isPreparingForSleep = true
        profileTask?.cancel()
        restoreAllDisabledDisplays(showMessage: false)
    }

    private func resumeDisplaySession(restoreDisabledDisplays: Bool) {
        isPreparingForSleep = false
        if restoreDisabledDisplays { restoreAllDisabledDisplays(showMessage: false) }
        handleDisplayTopologyChange()
    }

    private func handleDisplayTopologyChange() {
        recoverIfNoDisplayIsActive()
        refresh()

        // WindowServer updates the active-display list asynchronously. Check a
        // few more times so an abrupt cable removal cannot slip between events.
        recoveryTask?.cancel()
        recoveryTask = Task { @MainActor [weak self] in
            // These cumulative delays check at 0.25, 0.75 and 1.5 seconds.
            for delay in [250_000_000, 500_000_000, 750_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self else { return }
                self.recoverIfNoDisplayIsActive()
                self.refresh()
            }
        }
        scheduleProfileApplication()
    }

    private func scheduleProfileApplication() {
        profileTask?.cancel()
        guard remembersDisplayConfigurations, !isPreparingForSleep else { return }
        profileTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled, let self, !self.isPreparingForSleep else { return }
            self.applyRememberedDisplayConfiguration()
        }
    }

    private func applyRememberedDisplayConfiguration() {
        removeStaleDisabledDisplayIDs()
        guard remembersDisplayConfigurations,
              !recoveryInProgress,
              let context = currentDisplayContext(),
              let profile = savedProfile(for: context),
              let activeIDs = activeDisplayIDs(),
              !activeIDs.isEmpty else { return }

        var targets = context.ids.filter { context.matches(profile.fingerprints, displayID: $0) }
        if targets.count == context.ids.count {
            // Older versions could persist both displays as disabled when
            // WindowServer kept a stale ID. Keep the active external display.
            let keepID = activeIDs.first(where: { CGDisplayIsBuiltin($0) == 0 })
                ?? activeIDs.first!
            targets.removeAll { $0 == keepID }
        }
        let targetIDs = Set(targets)
        if targets.contains(where: { CGDisplayIsBuiltin($0) != 0 }) {
            // A stale connection record must never be enough to turn off the
            // built-in screen. Require a currently active external display.
            guard context.ids.contains(where: {
                CGDisplayIsBuiltin($0) == 0 && CGDisplayIsActive($0) != 0
            }) else { return }
        }

        let canonicalFingerprints = targets.map(context.fingerprint(for:)).sorted()
        if profile.key != context.profileKey || profile.fingerprints != Set(canonicalFingerprints) {
            var profiles = savedDisplayProfiles()
            profiles[context.profileKey] = canonicalFingerprints
            preferences.set(profiles, forKey: profilesDefaultsKey)
        }

        // Restore screens first, then disable remembered targets. This ordering
        // guarantees that applying a profile never passes through a zero-screen
        // state, even when the remembered configuration changed substantially.
        for id in context.ids where disabledDisplayIDs.contains(id) && !targetIDs.contains(id) {
            setBlackout(false, for: id, rememberPreference: false)
        }

        var activeCount = activeDisplayIDs()?.count ?? 0
        for id in targets where !disabledDisplayIDs.contains(id) && CGDisplayIsActive(id) != 0 {
            guard activeCount > 1 else { break }
            setBlackout(true, for: id, rememberPreference: false)
            activeCount -= 1
        }
    }

    private func rememberDisplayPreference(
        _ disabled: Bool,
        for displayID: CGDirectDisplayID,
        in context: DisplayContext
    ) {
        guard remembersDisplayConfigurations else { return }
        var desired = context.inactiveIDs
        if disabled { desired.insert(displayID) }
        else { desired.remove(displayID) }

        // The user's last deliberate switch is authoritative. Do not infer a
        // new preference from the temporary safety restore around sleep.
        var profiles = savedDisplayProfiles()
        profiles[context.profileKey] = desired.map(context.fingerprint(for:)).sorted()
        preferences.set(profiles, forKey: profilesDefaultsKey)
    }

    private func savedProfile(
        for context: DisplayContext
    ) -> (key: String, fingerprints: Set<String>)? {
        let profiles = savedDisplayProfiles()
        if let values = profiles[context.profileKey] {
            return (context.profileKey, Set(values))
        }
        if let values = profiles[context.legacyProfileKey] {
            return (context.legacyProfileKey, Set(values))
        }
        return nil
    }

    private func savedDisplayProfiles() -> [String: [String]] {
        let rawProfiles = preferences.dictionary(forKey: profilesDefaultsKey) ?? [:]
        return rawProfiles.reduce(into: [:]) { result, entry in
            if let values = entry.value as? [String] { result[entry.key] = values }
        }
    }

    private func currentDisplayContext() -> DisplayContext? {
        var ids = connectedDisplayIDs()
        guard ids.contains(where: { CGDisplayIsBuiltin($0) == 0 }) else { return nil }
        ids.sort()
        let fingerprints = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayFingerprint(for: $0)) })
        let aliases = Dictionary(uniqueKeysWithValues: ids.map { ($0, displayAliases(for: $0)) })
        let externalIDs = ids.filter { CGDisplayIsBuiltin($0) == 0 }
        let key = "external:" + externalIDs.map { fingerprints[$0]! }.sorted().joined(separator: "|")
        let legacyKey = "external:" + externalIDs.map { id in
            displayUUID(for: id) ?? fingerprints[id]!
        }.sorted().joined(separator: "|")
        return DisplayContext(
            profileKey: key,
            legacyProfileKey: legacyKey,
            ids: ids,
            inactiveIDs: Set(ids.filter {
                disabledDisplayIDs.contains($0) && CGDisplayIsActive($0) == 0
            }),
            fingerprints: fingerprints,
            aliases: aliases
        )
    }

    private func connectedDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids: [CGDirectDisplayID] = []
        if CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 {
            var onlineIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
            if CGGetOnlineDisplayList(count, &onlineIDs, &count) == .success {
                ids.append(contentsOf: onlineIDs.prefix(Int(count)))
            }
        }
        // A display disabled by LumaDeck can disappear from the public online
        // list, so add only our own known-disabled IDs. Do not use WindowServer's
        // broader list here: it can retain a just-unplugged external display for
        // a short time and would make an old profile unsafe to reapply.
        for id in disabledDisplayIDs where !ids.contains(id) { ids.append(id) }
        return ids
    }

    private func displayFingerprint(for displayID: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        if vendor != 0 && model != 0 && serial != 0 {
            return "hardware:\(vendor)-\(model)-\(serial)-\(CGDisplayIsBuiltin(displayID))"
        }
        return displayUUID(for: displayID) ?? "hardware:\(vendor)-\(model)-\(serial)-\(CGDisplayIsBuiltin(displayID))"
    }

    private func displayAliases(for displayID: CGDirectDisplayID) -> Set<String> {
        var aliases: Set<String> = [displayFingerprint(for: displayID)]
        if let uuid = displayUUID(for: displayID) { aliases.insert(uuid) }
        return aliases
    }

    private func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        if let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let uuid = unmanagedUUID.takeRetainedValue()
            if let value = CFUUIDCreateString(nil, uuid) as String? {
                return "uuid:" + value.lowercased()
            }
        }
        return nil
    }

    private func recoverIfNoDisplayIsActive() {
        guard !disabledDisplayIDs.isEmpty,
              activeDisplayIDs()?.isEmpty == true else { return }
        restoreAllDisabledDisplays(showMessage: true)
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID]? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return Array(ids.prefix(Int(count)))
    }

    private func restoreAllDisabledDisplays(showMessage: Bool) {
        guard !recoveryInProgress, !disabledDisplayIDs.isEmpty else { return }
        recoveryInProgress = true
        defer { recoveryInProgress = false }

        var restored: [CGDirectDisplayID] = []
        for id in disabledDisplayIDs where powerController.setEnabled(true, displayID: id) {
            restored.append(id)
        }
        guard !restored.isEmpty else { return }

        disabledDisplayIDs.subtract(restored)
        saveDisabledDisplayIDs()
        refresh()
        if showMessage {
            lastError = "检测到没有可用显示器，已自动恢复被停用的屏幕。"
        }
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
