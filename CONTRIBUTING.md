# Contributing to LumaDeck

Thank you for helping improve LumaDeck. Display behavior varies widely across Mac hardware, cables, docks, and monitors, so reproducible reports are especially valuable.

## Before you start

- Search existing issues first.
- Use the bug or feature issue form.
- Do not include passwords, serial numbers, Apple Account details, or other sensitive information.
- Read [docs/PRIVATE_APIS.md](docs/PRIVATE_APIS.md) before changing display power or hardware brightness code.

## Development setup

Requirements:

- macOS 14 or later
- Xcode 16 or a Swift 6 toolchain

Build the Swift package:

```bash
swift build
```

Build the app bundle:

```bash
./scripts/build-app.sh release
```

Run the same checks used by CI:

```bash
swift build -c release
git diff --check
./scripts/package-release.sh release
```

## Bug reports

For display-specific bugs, include:

- Mac model and chip
- macOS version
- Built-in or external display
- Monitor manufacturer and model
- Connection path, such as USB-C, HDMI, DisplayPort, or dock
- Display arrangement and which display is primary
- Exact steps and expected/actual behavior
- Whether the problem reproduces after reconnecting the monitor

Do not publish a full system profile if it contains personal information.

## Pull requests

- Keep changes focused and explain the user-visible outcome.
- Preserve the safety rule that at least one display remains visible.
- Avoid introducing additional private APIs unless there is no public alternative and the risk is documented.
- Keep the app functional when dynamically loaded symbols are unavailable.
- Update `CHANGELOG.md` for user-visible changes.
- Ensure Debug and Release builds succeed without warnings introduced by the change.

## Commit messages

Use a short conventional prefix where practical:

- `feat:` new functionality
- `fix:` bug fix
- `docs:` documentation
- `refactor:` internal change without a user-visible behavior change
- `build:` build or CI changes

Chinese or English commit subjects are both welcome.

## License

By contributing, you agree that your contribution is licensed under the MIT License included in this repository.
