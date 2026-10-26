import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        let px = 36
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: px * 4, bitsPerPixel: 32) else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(px) / 18
        NSColor.black.setFill()
        let d = 14.6 * s
        NSBezierPath(ovalIn: NSRect(x: (CGFloat(px) - d) / 2, y: (CGFloat(px) - d) / 2,
                                    width: d, height: d)).fill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        let ew = 2.5 * s, eh = 5.4 * s
        let ey = (CGFloat(px) - eh) / 2 + 0.9 * s
        for cx in [7.0, 11.0] {
            let r = NSRect(x: CGFloat(cx) * s - ew / 2, y: ey, width: ew, height: eh)
            NSBezierPath(roundedRect: r, xRadius: ew / 2, yRadius: ew / 2).fill()
        }
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
