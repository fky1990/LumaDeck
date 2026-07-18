import SwiftUI
import CoreGraphics

struct DisplayPopoverView: View {
    @EnvironmentObject private var manager: DisplayManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LumaDeck").font(.headline)
                        Text("光屏管家").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { manager.refresh() } label: { Image(systemName: "arrow.clockwise") }
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

                Divider()
                HStack {
                    Button("设置") { openSettings() }
                    Spacer()
                    Button("退出 LumaDeck") { NSApplication.shared.terminate(nil) }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(width: 390, height: min(720, CGFloat(170 + manager.displays.count * 300)))
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
    @State private var showingModes = false

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
                    .help("单屏软关闭/开启")
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

            Button { showingModes.toggle() } label: {
                HStack {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 24)
                    Text("分辨率与刷新率")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(display.currentResolution)
                        Text(display.currentRefreshRate).font(.caption).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingModes, arrowEdge: .trailing) {
                ModePicker(display: display, isPresented: $showingModes)
            }

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

private struct ModePicker: View {
    @EnvironmentObject private var manager: DisplayManager
    let display: DisplayDevice
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("显示模式").font(.headline).padding(.horizontal, 10)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(display.modes) { option in
                        Button {
                            manager.applyMode(option, to: display.id)
                            isPresented = false
                        } label: {
                            HStack {
                                Image(systemName: option.id == display.currentMode?.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(option.id == display.currentMode?.id ? Color.accentColor : .secondary)
                                Text(option.resolutionLabel)
                                if option.isHiDPI { Text("HiDPI").font(.caption2).foregroundStyle(.blue) }
                                Spacer()
                                Text(option.refreshLabel).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(width: 310, height: 380)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var manager: DisplayManager

    var body: some View {
        Form {
            Section("关于 LumaDeck") {
                LabeledContent("名称", value: "LumaDeck（光屏管家）")
                LabeledContent("版本", value: "0.1.0")
            }
            Section("控制方式") {
                Text("亮度优先使用显示器硬件接口；硬件不支持时自动使用无色偏的软件调光遮罩。")
                Text("显示器开关是单屏软关闭：画面被完全遮黑，但不会切断显示器电源，也不会改变桌面排列。")
            }
            Section("提示") {
                Text("修改分辨率或刷新率时屏幕会短暂闪烁，这是 macOS 切换显示模式的正常现象。")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 390)
    }
}
