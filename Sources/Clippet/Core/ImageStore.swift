import AppKit
import ImageIO

enum ImageStore {

    static var dataProvider: ((Int64) -> Data?)?

    private static let thumbCache: NSCache<NSNumber, NSImage> = {
        let c = NSCache<NSNumber, NSImage>()
        c.countLimit = 120

        c.totalCostLimit = 32 * 1024 * 1024
        return c
    }()

    private static let sizeCache: NSCache<NSNumber, NSValue> = {
        let c = NSCache<NSNumber, NSValue>()
        c.countLimit = 400
        return c
    }()

    private static let dataCache: NSCache<NSNumber, NSData> = {
        let c = NSCache<NSNumber, NSData>()
        c.countLimit = 12
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    private static let fileIconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 80
        return c
    }()

    static func fileIcon(forPath path: String) -> NSImage? {
        let key = path as NSString
        if let cached = fileIconCache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        fileIconCache.setObject(icon, forKey: key)
        return icon
    }

    static func pixelSize(forID id: Int64, data: Data) -> CGSize? {
        let key = NSNumber(value: id)
        if let cached = sizeCache.object(forKey: key) { return cached.sizeValue }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        let size = CGSize(width: w, height: h)
        sizeCache.setObject(NSValue(size: size), forKey: key)
        return size
    }

    static func thumbnail(forID id: Int64, maxDimension: CGFloat = 520) -> NSImage? {
        let key = NSNumber(value: id)
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let data = fullData(forID: id) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbCache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }

    static func fullData(forID id: Int64) -> Data? {
        let key = NSNumber(value: id)
        if let cached = dataCache.object(forKey: key) { return cached as Data }
        guard let data = dataProvider?(id) else { return nil }
        dataCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    /// Drops raw image bytes but keeps decoded thumbnails, so the next panel
    /// show does not have to decode the cards it is about to display again.
    static func purgeFullSize() {
        dataCache.removeAllObjects()
    }

    static func purge() {
        thumbCache.removeAllObjects()
        sizeCache.removeAllObjects()
        dataCache.removeAllObjects()
        fileIconCache.removeAllObjects()
    }
}

enum CheckerTile {
    static let image: NSImage = {
        let s: CGFloat = 7
        let image = NSImage(size: NSSize(width: s * 2, height: s * 2))
        image.lockFocus()
        NSColor(white: 0.24, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: s * 2, height: s * 2).fill()
        NSColor(white: 0.32, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        NSRect(x: s, y: s, width: s, height: s).fill()
        image.unlockFocus()
        return image
    }()
}
