import AppKit

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    static func transparent(size: NSSize) -> ClipboardPanel {
        let p = ClipboardPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.titled, .fullSizeContentView],
                               backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        return p
    }
}
