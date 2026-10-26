import AppKit

enum PanelFrameStore {
    private static let key = "panel.frame.v1"

    static func save(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: key)
    }

    static func savedFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: key), !raw.isEmpty else { return nil }
        let rect = NSRectFromString(raw)
        guard rect.width > 1, rect.height > 1 else { return nil }
        return rect
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func isUsable(_ frame: NSRect, on screen: NSScreen) -> Bool {
        let visible = screen.visibleFrame
        let overlap = frame.intersection(visible)
        guard !overlap.isNull else { return false }

        return overlap.height >= frame.height * 0.6
    }
}
