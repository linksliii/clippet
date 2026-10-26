#if DEBUG
import AppKit
import SwiftUI

enum Snapshot {

    @MainActor
    static func run(outputPath: String) {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippetSnapshot-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let db = try? Database.open(at: tempDir.appendingPathComponent("snap.db")) else {
            print("snapshot: db open failed")
            exit(1)
        }
        let repo = Repository(db: db)
        seed(repo)

        let model = ClipboardViewModel(repo: repo)
        model.reload(resetSelection: true)
        model.selection = 2

        let renderer = ImageRenderer(content: HistoryView(model: model))
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            print("snapshot: render failed")
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("snapshot: encode failed")
            exit(1)
        }
        do {
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("snapshot written: \(outputPath) (\(data.count) bytes)")
        } catch {
            print("snapshot: write failed: \(error)")
            exit(1)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    static func settingsPanes(outputDirectory: String) {
        _ = NSApplication.shared
        let settings = AppSettings.shared
        let apps = [
            AppUsage(bundleID: "com.apple.Safari", name: "Safari", count: 42),
            AppUsage(bundleID: "com.apple.dt.Xcode", name: "Xcode", count: 17),
            AppUsage(bundleID: "com.apple.Terminal", name: "Terminal", count: 9)
        ]
        try? FileManager.default.createDirectory(atPath: outputDirectory,
                                                 withIntermediateDirectories: true)
        for pane in SettingsPane.allCases {
            let view = SettingsView(settings: settings, knownApps: apps, initialPane: pane)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage else {
                print("render failed: \(pane.rawValue)"); continue
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let path = (outputDirectory as NSString).appendingPathComponent("\(pane.rawValue).png")
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
        exit(0)
    }

    private static func seed(_ repo: Repository) {
        insert(repo, kind: .text,
               text: "Hey team — attaching the revised design doc for the onboarding flow. Let me know if the copy changes land right.",
               tags: [], app: ("com.tinyspeck.slackmacgap", "Slack"), secondsAgo: 40)

        insert(repo, kind: .link,
               text: "https://developer.apple.com/documentation/appkit/nspasteboard",
               tags: ["url"], app: ("com.apple.Safari", "Safari"), secondsAgo: 120)

        insert(repo, kind: .code,
               text: "func trim(capacity: Int) {\n    guard capacity > 0 else { return }\n    db.run(\"DELETE FROM items …\")\n}",
               tags: ["code"], app: ("com.apple.dt.Xcode", "Xcode"), secondsAgo: 300)

        insert(repo, kind: .image, imageSize: CGSize(width: 1024, height: 1024),
               filename: "Image 1024×1024", tags: ["image"],
               app: ("com.apple.Preview", "Preview"), secondsAgo: 900)

        insert(repo, kind: .file,
               text: "/Users/links/Documents/Q3-report.pdf",
               paths: ["/Users/links/Documents/Q3-report.pdf"], filename: "Q3-report.pdf",
               byteSize: 284_512, tags: [], app: ("com.apple.finder", "Finder"), secondsAgo: 1800)

        insert(repo, kind: .color, text: "#FF8800", tags: ["color"], app: nil, secondsAgo: 2600)

        insert(repo, kind: .text, text: "password: hunter2-correct-horse",
               tags: ["secret", "password-assign"], app: ("com.apple.Terminal", "Terminal"), secondsAgo: 3600)

        let items = repo.recent(limit: 20)
        if let link = items.first(where: { $0.kind == .link }) {
            repo.setPinned(link.id, true)
        }
        if let code = items.first(where: { $0.kind == .code }) {
            repo.setSnippet(code.id, true)
        }
    }

    private static func insert(_ repo: Repository,
                               kind: ClipKind,
                               text: String? = nil,
                               imageSize: CGSize? = nil,
                               paths: [String] = [],
                               filename: String? = nil,
                               byteSize: Int? = nil,
                               tags: [String],
                               app: (String, String)?,
                               secondsAgo: TimeInterval) {
        var c = ClassifiedContent(kind: kind)
        c.text = text
        c.paths = paths
        c.filename = filename
        c.tags = tags

        if let size = imageSize {
            c.data = makePNG(size: size)
            c.byteSize = c.data?.count ?? 0
        } else if let explicit = byteSize {
            c.byteSize = explicit
        } else {
            c.byteSize = (text ?? "").utf8.count
        }

        c.preview = text ?? filename ?? kind.displayName
        c.hash = "\(kind.rawValue)-\(text ?? filename ?? UUID().uuidString)-\(secondsAgo)"

        _ = repo.insert(c, sourceApp: app?.0, sourceName: app?.1)

        if let newest = repo.recent(limit: 1).first {
            let when = Date().timeIntervalSince1970 - secondsAgo
            _ = try? repo.setCreatedAt(id: newest.id, when)
        }
    }

    private static func makePNG(size: CGSize) -> Data? {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: 0.35, green: 0.55, blue: 0.86, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: size.width * 0.25, y: size.height * 0.25,
                                    width: size.width * 0.5, height: size.height * 0.5)).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

#endif
