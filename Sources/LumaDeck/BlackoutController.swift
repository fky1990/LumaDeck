import AppKit
import CoreGraphics

@MainActor
final class BlackoutController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var dimming: [CGDirectDisplayID: Double] = [:]
    private var blackout = Set<CGDirectDisplayID>()

    func isBlackout(displayID: CGDirectDisplayID) -> Bool { blackout.contains(displayID) }

    func reconcile(activeDisplayIDs: Set<CGDirectDisplayID>) {
        let missing = Set(windows.keys).subtracting(activeDisplayIDs)
        for id in missing {
            windows[id]?.orderOut(nil)
            windows[id] = nil
            dimming[id] = nil
            blackout.remove(id)
        }

        // A hot-unplug must never leave the only remaining screen blacked out.
        if !activeDisplayIDs.isEmpty && activeDisplayIDs.allSatisfy({ blackout.contains($0) }) {
            let restoreID = activeDisplayIDs.first!
            blackout.remove(restoreID)
            update(restoreID)
        }
    }

    func setBlackout(_ enabled: Bool, displayID: CGDirectDisplayID) {
        if enabled { blackout.insert(displayID) } else { blackout.remove(displayID) }
        update(displayID)
    }

    func setDimming(_ amount: Double, displayID: CGDirectDisplayID) {
        dimming[displayID] = min(0.95, max(0, amount))
        update(displayID)
    }

    private func update(_ displayID: CGDirectDisplayID) {
        let alpha = blackout.contains(displayID) ? 1 : (dimming[displayID] ?? 0)
        guard alpha > 0.001 else {
            windows[displayID]?.orderOut(nil)
            windows[displayID] = nil
            return
        }

        guard let screen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == displayID
        }) else { return }

        let window = windows[displayID] ?? makeWindow(screen: screen)
        window.setFrame(screen.frame, display: true)
        window.alphaValue = alpha
        window.orderFrontRegardless()
        windows[displayID] = window
    }

    private func makeWindow(screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .black
        window.isOpaque = true
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }
}
