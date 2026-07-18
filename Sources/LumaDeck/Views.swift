import SwiftUI
import CoreGraphics

struct DisplayPopoverView: View {
    @EnvironmentObject private var manager: DisplayManager

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LumaDeck").font(.headline)
                        Text("光屏管家").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { manager.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(.quaternary, in: Circle())
                    }
                        .buttonStyle(.plain)
                        .help("刷新显示器")
                }
                .padding(.horizontal, 4)

                if manager.displays.isEmpty {
                    ContentUnavailableView("未发现显示器", systemImage: "display.trianglebadge.exclamationmark")
                        .frame(height: 180)
                } else {
                    ForEach(manager.displays) { display in
                        DisplayCard(display: display)
                    }
                }

                HStack(spacing: 10) {
                    SettingsLink {
                        Label("偏好设置", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button { manager.quitAfterRestoringDisplays() } label: {
                        Label("退出", systemImage: "power")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(.red)
                            .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: 410, height: min(760, CGFloat(170 + manager.displays.count * 390)))
        .alert("LumaDeck", isPresented: Binding(
            get: { manager.lastError != nil },
            set: { if !$0 { manager.lastError = nil } }
        )) { Button("好") { manager.lastError = nil } } message: {
            Text(manager.lastError ?? "")
        }
    }
}

private struct DisplayCard: View {
    @EnvironmentObject private var manager: DisplayManager
    let display: DisplayDevice

    private var brightness: Binding<Double> {
        Binding(get: { display.brightness }, set: { manager.setBrightness($0, for: display.id) })
    }

    private var enabled: Binding<Bool> {
        Binding(get: { !display.isBlackout }, set: { manager.setBlackout(!$0, for: display.id) })
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.title3)
                Text(display.name).font(.headline).lineLimit(1)
                if manager.isPrimary(display.id) {
                    Text("主屏").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.secondary.opacity(0.18), in: Capsule())
                }
                Spacer()
                Toggle("", isOn: enabled).labelsHidden().toggleStyle(.switch)
                    .help("停用/启用这台显示器")
            }

            VStack(spacing: 5) {
                HStack {
                    Text("亮度（组合）").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(display.brightness * 100))%") .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "sun.max.fill").foregroundStyle(.secondary).frame(width: 24)
                    Slider(value: brightness, in: 0.05...1)
                }
            }

            DisplayModeSliders(display: display)

            HStack {
                Label(display.isBuiltIn ? "内建显示屏" : "外接显示器", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !manager.isPrimary(display.id) {
                    Button("设为主显示器") { manager.makePrimary(display.id) }
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.separator.opacity(0.5)))
        .opacity(display.isBlackout ? 0.58 : 1)
    }
}

private struct ResolutionGroup: Identifiable {
    let id: String
    let label: String
    let modes: [DisplayModeOption]
}

private struct DisplayModeSliders: View {
    @EnvironmentObject private var manager: DisplayManager
    let display: DisplayDevice
    @State private var resolutionIndex: Int
    @State private var refreshIndex: Int

    init(display: DisplayDevice) {
        self.display = display
        let groups = Self.makeResolutionGroups(display.modes)
        let selectedResolution = groups.firstIndex(where: {
            $0.modes.contains(where: { $0.id == display.currentMode?.id })
        }) ?? 0
        _resolutionIndex = State(initialValue: selectedResolution)
        let modes = groups.indices.contains(selectedResolution) ? groups[selectedResolution].modes : []
        _refreshIndex = State(initialValue: modes.firstIndex(where: { $0.id == display.currentMode?.id }) ?? 0)
    }

    private var groups: [ResolutionGroup] { Self.makeResolutionGroups(display.modes) }

    private var selectedGroup: ResolutionGroup? {
        groups.indices.contains(resolutionIndex) ? groups[resolutionIndex] : groups.first
    }

    private var refreshModes: [DisplayModeOption] { selectedGroup?.modes ?? [] }

    private var resolutionLabel: String { selectedGroup?.label ?? display.currentResolution }

    private var refreshLabel: String {
        guard refreshModes.indices.contains(refreshIndex) else { return display.currentRefreshRate }
        return refreshModes[refreshIndex].refreshLabel
    }

    var body: some View {
        VStack(spacing: 12) {
            modeSlider(
                title: "分辨率",
                value: resolutionLabel,
                systemImage: "arrow.up.left.and.arrow.down.right",
                index: resolutionBinding,
                count: groups.count,
                onCommit: applyResolution
            )
            modeSlider(
                title: "刷新率",
                value: refreshLabel,
                systemImage: "gauge.with.dots.needle.67percent",
                index: refreshBinding,
                count: refreshModes.count,
                onCommit: applyRefreshRate
            )
        }
        .disabled(display.isBlackout || display.modes.isEmpty)
        .onChange(of: display.currentMode?.id) { _, _ in syncFromDisplay() }
    }

    private func modeSlider(
        title: String,
        value: String,
        systemImage: String,
        index: Binding<Double>,
        count: Int,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Label(title, systemImage: systemImage).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: systemImage).foregroundStyle(.tertiary).frame(width: 24)
                Slider(
                    value: index,
                    in: 0...Double(max(1, count - 1)),
                    step: 1,
                    onEditingChanged: { if !$0 { onCommit() } }
                )
                .disabled(count < 2)
            }
        }
    }

    private var resolutionBinding: Binding<Double> {
        Binding(
            get: { Double(resolutionIndex) },
            set: { value in
                resolutionIndex = min(max(0, Int(value.rounded())), max(0, groups.count - 1))
                refreshIndex = closestRefreshIndex(in: refreshModes, to: display.currentMode?.refreshRate ?? 0)
            }
        )
    }

    private var refreshBinding: Binding<Double> {
        Binding(
            get: { Double(refreshIndex) },
            set: { refreshIndex = min(max(0, Int($0.rounded())), max(0, refreshModes.count - 1)) }
        )
    }

    private func applyResolution() {
        guard let group = selectedGroup, !group.modes.isEmpty else { return }
        let currentRate = display.currentMode?.refreshRate ?? 0
        let option = group.modes.min(by: { abs($0.refreshRate - currentRate) < abs($1.refreshRate - currentRate) })!
        manager.applyMode(option, to: display.id)
    }

    private func applyRefreshRate() {
        guard refreshModes.indices.contains(refreshIndex) else { return }
        manager.applyMode(refreshModes[refreshIndex], to: display.id)
    }

    private func syncFromDisplay() {
        guard let current = display.currentMode else { return }
        if let groupIndex = groups.firstIndex(where: { group in group.modes.contains(where: { $0.id == current.id }) }) {
            resolutionIndex = groupIndex
            refreshIndex = groups[groupIndex].modes.firstIndex(where: { $0.id == current.id }) ?? 0
        }
    }

    private func closestRefreshIndex(in modes: [DisplayModeOption], to rate: Double) -> Int {
        modes.indices.min(by: { abs(modes[$0].refreshRate - rate) < abs(modes[$1].refreshRate - rate) }) ?? 0
    }

    private static func makeResolutionGroups(_ modes: [DisplayModeOption]) -> [ResolutionGroup] {
        var order: [String] = []
        var grouped: [String: [DisplayModeOption]] = [:]
        for mode in modes {
            let key = "\(mode.width)x\(mode.height)-\(mode.pixelWidth)x\(mode.pixelHeight)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(mode)
        }
        return order.compactMap { key in
            guard let values = grouped[key], let first = values.first else { return nil }
            let suffix = first.isHiDPI ? " · HiDPI" : ""
            let uniqueRates = Dictionary(grouping: values, by: { Int(($0.refreshRate * 100).rounded()) })
                .values.compactMap(\.first).sorted { $0.refreshRate < $1.refreshRate }
            return ResolutionGroup(id: key, label: first.resolutionLabel + suffix, modes: uniqueRates)
        }
    }
}

struct SettingsView: View {
    @StateObject private var loginItem = LoginItemManager()

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LumaDeck 偏好设置").font(.title2.bold())
                    Text("光屏管家 · 版本 0.1.9").foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 14) {
                Image(systemName: "power.circle.fill")
                    .font(.system(size: 28)).foregroundStyle(.blue)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("登录时自动启动").font(.headline)
                    Text("登录 macOS 后在菜单栏自动运行 LumaDeck。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { loginItem.isRegistered },
                    set: { loginItem.setEnabled($0) }
                ))
                .labelsHidden().toggleStyle(.switch)
            }
            .padding(16)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))

            if loginItem.requiresApproval {
                HStack {
                    Label("需要在系统设置中批准登录项", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("打开系统设置") { loginItem.openLoginItemSettings() }
                }
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 500, height: 260)
        .onAppear { loginItem.refresh() }
        .alert("无法更新开机自启动", isPresented: Binding(
            get: { loginItem.errorMessage != nil },
            set: { if !$0 { loginItem.errorMessage = nil } }
        )) { Button("好") { loginItem.errorMessage = nil } } message: {
            Text(loginItem.errorMessage ?? "")
        }
    }
}
