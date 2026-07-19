# Private APIs and compatibility

The full GitHub build contains optional integrations with undocumented macOS APIs. They are dynamically resolved so the app can fall back safely when unavailable, but dynamic loading does not make them public or stable.

## Hardware brightness

`BrightnessController` loads:

- `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices`
- `DisplayServicesGetBrightness`
- `DisplayServicesSetBrightness`

When unavailable or unsupported by a display, LumaDeck uses a mouse-transparent black overlay for software dimming. Software dimming changes perceived brightness; it does not reduce the monitor backlight.

## Display disabling

`DisplayPowerController` resolves these CoreGraphics implementation symbols:

- `CGSConfigureDisplayEnabled`
- `CGSGetDisplayList`

The first removes a display from the active desktop configuration. The second is used to find attached displays that disappear from public online-display enumeration after being disabled.

## Risks

- Apple can rename, remove, or change these symbols without notice.
- Behavior can differ across macOS versions and Mac hardware.
- A macOS update can make a previously working binary fail to control or recover a display.
- Apps using private APIs are not eligible for the Mac App Store under App Review Guideline 2.5.1.
- Apple does not provide support or compatibility guarantees for these calls.

## Safety behavior

- Symbol lookup failure is treated as an unsupported capability, not a fatal error.
- LumaDeck blocks disabling the final visible display.
- Disabled IDs are stored locally and restored on the next launch.
- Normal app exit attempts to restore every display disabled by LumaDeck.
- A software blackout fallback remains available when true disabling fails.

## Distribution guidance

Source builds and GitHub binaries should clearly disclose this behavior. Production GitHub binaries should be Developer ID signed and notarized. An App Store flavor must compile without these controllers or any private symbol and should relabel the fallback as software dimming/blackout rather than display power control.
