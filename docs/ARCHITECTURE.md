# Architecture

LumaDeck is a small native macOS menu bar app built as a Swift Package executable.

## Application layers

### UI

- `LumaDeckApp.swift` defines the `MenuBarExtra` and Settings scene.
- `Views.swift` contains the display cards, independent sliders, settings UI, and foreground-window handling.

### Display model and orchestration

- `DisplayManager.swift` discovers displays, caches names and modes, applies user actions, watches topology notifications, and enforces safety rules.
- Display state is rebuilt from CoreGraphics and `NSScreen` rather than treated as a permanent cache.

### Controllers

- `BrightnessController.swift` dynamically loads hardware-brightness functions when available.
- `DisplayPowerController.swift` dynamically loads display-enabled configuration functions and enumerates displays that public online-display APIs omit after disabling.
- `BlackoutController.swift` provides a public-AppKit software dimming and blackout fallback using a borderless, mouse-transparent per-screen window.
- `LoginItemManager.swift` wraps the public `SMAppService.mainApp` API.

## Display mode model

Each `DisplayModeOption` retains its `CGDisplayMode` object together with logical size, pixel size, and refresh rate. A mode is treated as HiDPI when its pixel dimensions exceed its logical dimensions. LumaDeck presents only HiDPI modes when at least one is available, avoiding accidental low-resolution selections.

Resolution groups are independent from refresh-rate choices. Selecting a new logical resolution preserves the closest supported refresh rate where possible.

## Safety invariants

- Never allow the user to hide the last visible display.
- Restore displays disabled by LumaDeck before a normal quit.
- Persist disabled display IDs so an interrupted run can recover them on the next launch.
- Keep private capabilities optional; the app must remain usable when their symbols are unavailable.
- Reconcile overlay windows whenever the active display list changes.

## Build artifacts

`scripts/build-app.sh` compiles the Swift package, assembles a standard `.app` bundle, copies resources, and applies an ad-hoc signature. `scripts/package-release.sh` produces a versioned ZIP and checksum for testing.

Production distribution requires Developer ID signing and Apple notarization. The tag workflow deliberately creates a draft release because its CI artifact is only ad-hoc signed; a maintainer should replace or sign and notarize that artifact before publishing the release. Mac App Store distribution additionally requires an Xcode archive, App Sandbox, and removal of private APIs.
