# Changelog

All notable user-visible changes are documented here. The project follows semantic versioning after the 1.0 release; 0.x releases may still contain compatibility changes.

## [Unreleased]

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

[Unreleased]: https://github.com/fky1990/LumaDeck/compare/v0.1.10...HEAD
[0.1.10]: https://github.com/fky1990/LumaDeck/releases/tag/v0.1.10
