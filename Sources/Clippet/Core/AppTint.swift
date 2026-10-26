import AppKit

enum AppTint {

    private static let tintCache = NSCache<NSString, NSString>()

    private static let iconCache = NSCache<NSString, NSImage>()

    static func tint(forBundleID bundleID: String?) -> String? {
        guard let bundleID = bundleID, !bundleID.isEmpty else { return nil }
        if let cached = tintCache.object(forKey: bundleID as NSString) { return cached as String }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        guard let hex = vividColor(from: icon) else { return nil }
        tintCache.setObject(hex as NSString, forKey: bundleID as NSString)
        return hex
    }

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID = bundleID, !bundleID.isEmpty else { return nil }
        if let cached = iconCache.object(forKey: bundleID as NSString) { return cached }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        iconCache.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    static func displayDomain(for url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = url.path
        if path == "/" { path = "" }
        var query = url.query.map { "?\($0)" } ?? ""
        if query.count > 40 { query = "" }
        return stripped + path + query
    }

    static func vividColor(from image: NSImage) -> String? {
        let side = 64
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: side * 4, bitsPerPixel: 32) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }

        var sinSum: Double = 0
        var cosSum: Double = 0
        var weightSum: Double = 0
        var fallbackR: Double = 0, fallbackG: Double = 0, fallbackB: Double = 0, fallbackW: Double = 0

        for y in 0..<side {
            for x in 0..<side {
                let offset = y * rep.bytesPerRow + x * 4
                let a = Double(data[offset + 3]) / 255.0
                guard a > 0.4 else { continue }
                let r = Double(data[offset]) / 255.0
                let g = Double(data[offset + 1]) / 255.0
                let b = Double(data[offset + 2]) / 255.0

                var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
                NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
                    .getHue(&h, saturation: &s, brightness: &br, alpha: &al)

                fallbackR += r; fallbackG += g; fallbackB += b; fallbackW += 1

                guard s > 0.30, br > 0.20 else { continue }
                let angle = Double(h) * 2 * .pi
                let w = Double(s)
                sinSum += sin(angle) * w
                cosSum += cos(angle) * w
                weightSum += w
            }
        }

        var hue: Double = 0
        if weightSum > 0.001 {
            hue = atan2(sinSum, cosSum) / (2 * .pi)
            if hue < 0 { hue += 1 }
        } else if fallbackW > 0 {
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
            NSColor(srgbRed: fallbackR / fallbackW, green: fallbackG / fallbackW,
                    blue: fallbackB / fallbackW, alpha: 1)
                .getHue(&h, saturation: &s, brightness: &br, alpha: &al)
            hue = Double(h)
        } else {
            return nil
        }

        let out = NSColor(hue: CGFloat(hue), saturation: 0.86, brightness: 0.93, alpha: 1)
        return out.hexString
    }
}
