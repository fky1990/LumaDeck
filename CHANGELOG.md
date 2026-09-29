# Changelog

All notable user-visible changes are documented here. The project follows semantic versioning after the 1.0 release; 0.x releases may still contain compatibility changes.

## [Unreleased]

## [0.1.12] - 2026-09-30

### Added

- 按外接显示器硬件组合记忆屏幕开关状态，并在再次连接时自动恢复上一次的使用习惯。

### Fixed

- 非 Apple 外接显示器不再因 DisplayServices 的假成功结果而忽略软件调光。
- 解锁或唤醒后重新应用已保存的屏幕开关状态，并修复禁用屏幕后显示器身份变化导致的配置匹配失败。

## [0.1.11] - 2026-07-20

### Fixed

- 在最后一块启用的显示器被拔掉时，立即恢复由 LumaDeck 停用的显示器，避免无屏可用。
- 在系统睡眠与唤醒前后恢复停用的显示器，避免开盖后持续黑屏。

## [0.1.10] - 2026-07-18

### Added

- Per-display brightness with hardware control and software dimming fallback.
- Independent resolution and refresh-rate sliders.
- HiDPI-only resolution list by default.
- Primary-display selection.
- Display disabling with recovery of displays disabled in a previous session.
- Login-at-startup preference.
- Native LumaDeck app icon.

### Fixed

- Preserve the selected primary display after changing resolution.
- Prevent repeated cursor movement during display reconfiguration.
- Restore disabled built-in displays when LumaDeck starts again.
- Bring the Settings window to the foreground when opened from the menu bar.

### Removed

- Unreliable Dock pinning behavior.

[Unreleased]: https://github.com/fky1990/LumaDeck/compare/v0.1.12...HEAD
[0.1.12]: https://github.com/fky1990/LumaDeck/releases/tag/v0.1.12
[0.1.11]: https://github.com/fky1990/LumaDeck/releases/tag/v0.1.11
[0.1.10]: https://github.com/fky1990/LumaDeck/releases/tag/v0.1.10
