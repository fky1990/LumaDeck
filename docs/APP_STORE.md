# Mac App Store compatibility

The full LumaDeck build cannot be submitted to the Mac App Store unchanged.

## Required changes

1. Create an Xcode app target and archive using an Apple Developer team.
2. Enable App Sandbox with the minimum necessary entitlements.
3. Remove `DisplayPowerController` and every reference to `CGSConfigureDisplayEnabled` and `CGSGetDisplayList`.
4. Remove `BrightnessController` and every reference to `DisplayServices.framework` and `DisplayServicesGet/SetBrightness`.
5. Present brightness as software dimming only.
6. Remove or relabel the display on/off switch because a black overlay does not remove a display from the desktop.
7. Test every remaining CoreGraphics configuration operation inside App Sandbox.
8. Replace the local ad-hoc signature with Mac App Distribution signing and an App Store provisioning profile.
9. Add App Store metadata, screenshots, support URL, and privacy-policy URL.

## Features that can remain

- Menu bar interface and Settings window
- Display discovery and names
- HiDPI resolution discovery and filtering
- Resolution and refresh-rate switching using public CoreGraphics APIs
- Primary-display selection using public display-configuration APIs
- Software dimming using AppKit windows, subject to sandbox testing and review
- Login at startup through `SMAppService`
- Local preferences and display-topology notifications

## Features removed from the App Store flavor

- Hardware backlight brightness through `DisplayServices`
- True display disabling through `CGSConfigureDisplayEnabled`
- Enumeration and automatic recovery that depends on `CGSGetDisplayList`

## Recommended source structure

Use protocols for brightness and display power, with two implementations:

- Full GitHub flavor: optional private hardware/display-power implementations plus public fallbacks.
- App Store flavor: public software-dimming implementation and no true display-power implementation.

A compile-time build setting such as `LUMADECK_APP_STORE` should ensure private symbol strings do not appear in the App Store binary.

## Important distinction

Open-source availability does not make private API use acceptable for App Store review. GitHub and Mac App Store distribution can coexist, but each binary must comply with the rules of its distribution channel.
