# LumaDeck

<p align="center">
  <img src="Resources/LumaDeckIcon.png" width="160" alt="LumaDeck app icon">
</p>

<p align="center">
  A native macOS menu bar utility for managing built-in and external displays.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="LICENSE">MIT License</a> ·
  <a href="PRIVACY.md">Privacy</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

> [!WARNING]
> The full GitHub build uses dynamically resolved, undocumented macOS APIs for hardware brightness and true display disabling. These features can break after a macOS update and are not eligible for the Mac App Store. Read [Private APIs and compatibility](docs/PRIVATE_APIS.md) before installing or distributing the app.

## Features

- Detect built-in and connected external displays.
- Adjust each display independently.
- Use hardware brightness when supported, with per-display software dimming as a fallback.
- Change HiDPI resolution and refresh rate with separate sliders.
- Hide non-HiDPI modes by default, with a compatibility fallback when none exist.
- Set any active display as the primary display.
- Disable a display while keeping at least one visible screen available.
- Remember display on/off preferences for each external-monitor setup.
- Restore displays disabled by LumaDeck after an interrupted session.
- Refresh automatically when the display topology changes.
- Start automatically at login using `SMAppService`.
- Run entirely from the macOS menu bar.

## Requirements

- macOS 14 or later
- Swift 6 toolchain / Xcode 16 or later
- Apple silicon or Intel Mac

The app is developed and tested primarily on macOS 27. Display control behavior can differ by Mac model, GPU, cable, dock, and monitor firmware.

## Build and run

```bash
git clone https://github.com/fky1990/LumaDeck.git
cd LumaDeck
./scripts/build-app.sh release
open outputs/LumaDeck.app
```

You can also open `Package.swift` directly in Xcode.

The local build is ad-hoc signed. macOS may ask for confirmation the first time you open it. Official GitHub Releases should be Developer ID signed and notarized before they are presented as production downloads.

## Release package

```bash
./scripts/package-release.sh release
```

The script builds the app, validates its signature, creates a versioned ZIP in `outputs/`, and writes a SHA-256 checksum.

## How it works

LumaDeck is a SwiftUI menu bar app backed by AppKit and CoreGraphics. Public Quartz Display Services APIs handle discovery, display modes, refresh rates, and display arrangement. A borderless per-screen AppKit window provides software dimming.

The full build additionally resolves `DisplayServices` and `CGS` symbols at runtime for capabilities that Apple does not expose through public APIs. See [Architecture](docs/ARCHITECTURE.md) and [Private APIs](docs/PRIVATE_APIS.md).

## Mac App Store

This repository is **not App Store ready as-is**. An App Store build must enable App Sandbox and remove hardware brightness and true display disabling. Resolution, refresh rate, display discovery, primary-display selection, software dimming, and login launch can remain. See [Mac App Store compatibility](docs/APP_STORE.md).

## Privacy

LumaDeck works locally, contains no analytics or advertising SDKs, and does not transmit display information. See [PRIVACY.md](PRIVACY.md).

## Contributing

Bug reports and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md), use the issue templates, and include your Mac model, macOS version, connection type, and monitor model when reporting display-specific problems.

## License

LumaDeck is available under the [MIT License](LICENSE). The license does not grant rights to Apple private APIs and does not guarantee compatibility with future macOS versions.
