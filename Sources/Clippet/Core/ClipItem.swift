import AppKit
import Foundation

enum ClipKind: String, CaseIterable, Codable {
    case text
    case link
    case image
    case file
    case color
    case code

    var displayName: String {
        switch self {
        case .text, .code: return "文本"
        case .link: return "链接"
        case .image: return "图片"
        case .file: return "文件"
        case .color: return "颜色"
        }
    }

}

struct ClipItem: Identifiable, Equatable {
    var id: Int64 = 0

    var boardID: Int64 = 0
    var kind: ClipKind

    var text: String?

    var data: Data?

    var paths: [String] = []
    var filename: String?
    var uti: String?
    var preview: String = ""
    var tags: [String] = []
    var sourceApp: String?
    var sourceAppName: String?

    var sourceTint: String?

    var linkTitle: String?
    var createdAt: Date = Date()
    var isPinned: Bool = false
    var isSnippet: Bool = false
    var stackOrder: Int?
    var byteSize: Int = 0

    var hash: String = ""

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id && lhs.hash == rhs.hash &&
        lhs.isPinned == rhs.isPinned && lhs.isSnippet == rhs.isSnippet &&
        lhs.stackOrder == rhs.stackOrder && lhs.boardID == rhs.boardID
    }

    var sizeLabel: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(byteSize))
    }

    var imageSizeLabel: String? {
        guard kind == .image, let d = data,
              let size = NSBitmapImageRepLite.size(of: d) else { return nil }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    var isSensitive: Bool { tags.contains("secret") }

    var metaLabel: String {
        switch kind {
        case .text, .code:
            let count = (text ?? "").count
            return "\(count) 个字符"
        case .color:
            return ""
        case .image:
            return ""
        case .file:
            return paths.first ?? filename ?? ""
        case .link:
            guard let t = text, let url = URL(string: t) else { return text ?? "" }
            return AppTint.displayDomain(for: url)
        }
    }
}

enum NSBitmapImageRepLite {
    static func size(of data: Data) -> CGSize? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}

struct Board: Identifiable, Equatable {    var id: Int64 = 0
    var name: String

    var tint: String
    var sort: Int = 0
    var isDefault: Bool = false

    static let palette = ["#FF4D4D", "#FF9500", "#FFCC00", "#34C759",
                          "#00C7BE", "#0A84FF", "#5E5CE6", "#BF5AF2"]
}

enum PasteError: Error {
    case empty
    case missingPayload
}

#if DEBUG
extension ClipItem {
    func withText(_ t: String) -> ClipItem { var c = self; c.text = t; return c }
    func withPaths(_ p: [String]) -> ClipItem { var c = self; c.paths = p; return c }
}
#endif
