import AppKit

/// Remembers the panel's vertical spot as a distance above the usable bottom
/// edge of whichever display it is on. One shared value keeps the panel in the
/// same place when the pointer moves it to another display, and the distance
/// from the visible bottom survives Dock and resolution changes.
enum PanelFrameStore {
    private static let key = "panel.bottom.v3"
    private static let legacyKey = "panel.position.v2"

    static func save(_ frame: NSRect, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        UserDefaults.standard.set(Double(y - visible.minY), forKey: key)
    }

    static func savedBottomOffset() -> CGFloat? {
        if let stored = UserDefaults.standard.object(forKey: key) as? Double {
            return CGFloat(stored)
        }
        return migrateLegacyOffset()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    /// The previous format pinned the panel to one display. Convert that spot
    /// into the shared bottom offset so the upgrade does not lose the position.
    private static func migrateLegacyOffset() -> CGFloat? {
        guard let stored = UserDefaults.standard.dictionary(forKey: legacyKey),
              let display = stored["display"] as? Int,
              let bottom = stored["bottom"] as? Double,
              let screen = NSScreen.screens.first(where: {
                  displayID(of: $0) == CGDirectDisplayID(display)
              }) else {
            return nil
        }

        let y = screen.frame.minY + CGFloat(bottom)
        let offset = max(0, y - screen.visibleFrame.minY)
        UserDefaults.standard.set(Double(offset), forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        return offset
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value
    }
}
