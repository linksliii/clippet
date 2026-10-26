import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageNormalizer {

    static let maxDimension = 2560

    static let maxBytes = 8 * 1024 * 1024

    static func normalize(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Double) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? Double) ?? 0
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier

        if isPNG, max(width, height) <= Double(maxDimension), data.count <= maxBytes {
            return data
        }

        var pixelSize = max(width, height)
        if pixelSize == 0 { pixelSize = Double(maxDimension) }

        while pixelSize >= 256 {
            guard let cgImage = downscaledImage(source, maxPixel: Int(pixelSize)) else { return nil }
            if let png = encodePNG(cgImage), png.count <= maxBytes {
                return png
            }
            pixelSize *= 0.75
        }
        guard let cgImage = downscaledImage(source, maxPixel: 512) else { return nil }
        return encodePNG(cgImage)
    }

    private static func downscaledImage(_ source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumb
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
