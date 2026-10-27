import AppKit
import ImageIO

enum ImageStore {

    static var dataProvider: ((Int64) -> Data?)?

    private static let thumbCache: NSCache<NSNumber, NSImage> = {
        let c = NSCache<NSNumber, NSImage>()
        c.countLimit = 60

        c.totalCostLimit = 16 * 1024 * 1024
        return c
    }()

    private static let sizeCache: NSCache<NSNumber, NSValue> = {
        let c = NSCache<NSNumber, NSValue>()
        c.countLimit = 400
        return c
    }()

    private static let dataCache: NSCache<NSNumber, NSData> = {
        let c = NSCache<NSNumber, NSData>()
        c.countLimit = 3
        c.totalCostLimit = 6 * 1024 * 1024
        return c
    }()

    /// Decodes run one at a time at utility QoS: a screen full of screenshots
    /// is still seven or eight full PNG decodes, and doing them together at
    /// user-initiated priority competes with the panel's slide-in animation.
    private static let decodeQueue = DispatchQueue(label: "clippet.image-decode",
                                                   qos: .utility)

    static func thumbnailAndSizeAsync(forID id: Int64,
                                      maxDimension: CGFloat = 520) async -> (image: NSImage?, pixelSize: CGSize?) {
        await withCheckedContinuation { continuation in
            decodeQueue.async {
                let result = thumbnailAndSize(forID: id, maxDimension: maxDimension)
                continuation.resume(returning: result)
            }
        }
    }

    /// Decodes the thumbnails of recent screenshots while the app is idle, so
    /// the next panel show has them in the cache instead of decoding them
    /// while the slide-in animation is running.
    static func prewarm(ids: [Int64]) {
        let missing = ids.filter { thumbCache.object(forKey: NSNumber(value: $0)) == nil }
        guard !missing.isEmpty else { return }
        decodeQueue.async {
            for id in missing {
                _ = thumbnailAndSize(forID: id)
            }
        }
    }

    static func previewImageAsync(forID id: Int64,
                                  maxDimension: CGFloat = 1600) async -> NSImage? {
        await withCheckedContinuation { continuation in
            decodeQueue.async {
                continuation.resume(returning: previewImage(forID: id, maxDimension: maxDimension))
            }
        }
    }

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

    /// Cache-only lookup, for drawing already-decoded thumbnails without a
    /// decode (or a database read) on the main thread.
    static func cachedThumbnail(forID id: Int64) -> NSImage? {
        thumbCache.object(forKey: NSNumber(value: id))
    }

    static func thumbnail(forID id: Int64, maxDimension: CGFloat = 520) -> NSImage? {
        thumbnailAndSize(forID: id, maxDimension: maxDimension).image
    }

    /// Decodes the card thumbnail and reads the original pixel size from the
    /// same image source, so the card needs neither a second database read nor
    /// the full-size bytes kept around afterwards.
    static func thumbnailAndSize(forID id: Int64,
                                 maxDimension: CGFloat = 520) -> (image: NSImage?, pixelSize: CGSize?) {
        let key = NSNumber(value: id)
        let knownSize = sizeCache.object(forKey: key)?.sizeValue
        if let cached = thumbCache.object(forKey: key) {
            return (cached, knownSize)
        }
        guard let data = fullData(forID: id),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return (nil, knownSize)
        }

        var pixelSize = knownSize
        if pixelSize == nil,
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Double,
           let height = props[kCGImagePropertyPixelHeight] as? Double {
            pixelSize = CGSize(width: width, height: height)
            sizeCache.setObject(NSValue(size: pixelSize!), forKey: key)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            dataCache.removeObject(forKey: key)
            return (nil, pixelSize)
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbCache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        // The raw bytes were only needed for this decode; the thumbnail and the
        // pixel size are enough for the card.
        dataCache.removeObject(forKey: key)
        return (image, pixelSize)
    }

    /// Preview-sized decode: the popover never needs the original bytes decoded
    /// into a full-resolution NSImage.
    static func previewImage(forID id: Int64, maxDimension: CGFloat = 1600) -> NSImage? {
        let key = NSNumber(value: id)
        guard let data = fullData(forID: id) else { return nil }
        defer { dataCache.removeObject(forKey: key) }

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
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func fullData(forID id: Int64) -> Data? {
        let key = NSNumber(value: id)
        if let cached = dataCache.object(forKey: key) { return cached as Data }
        guard let data = dataProvider?(id) else { return nil }
        // Large originals are decoded once and not kept; the thumbnail cache is
        // what should survive for the next show.
        if data.count <= 4 * 1024 * 1024 {
            dataCache.setObject(data as NSData, forKey: key, cost: data.count)
        }
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
