#if DEBUG
import AppKit

enum Bench {

    static func run() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippetBench-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        guard let db = try? Database.open(at: tempDir.appendingPathComponent("bench.db")) else {
            print("bench: db open failed"); exit(1)
        }
        let repo = Repository(db: db)

        print("Clippet bench")
        print(String(repeating: "-", count: 52))

        var rowCount = 500
        if let i = CommandLine.arguments.firstIndex(of: "--rows"),
           i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]) {
            rowCount = n
        }

        let body = String(repeating: "lorem ipsum dolor sit amet consectetur ", count: 6)
        let seedStart = DispatchTime.now().uptimeNanoseconds
        for i in 0..<rowCount {
            var c = ClassifiedContent(kind: .text)
            c.text = "\(body) row \(i)"
            c.preview = c.text!
            c.byteSize = c.text!.utf8.count
            c.hash = "bench-\(i)"
            _ = repo.insert(c, sourceApp: "com.apple.Safari", sourceName: "Safari")
        }
        let seedMs = Double(DispatchTime.now().uptimeNanoseconds - seedStart) / 1_000_000
        print(String(format: "seeded %lld rows in %.0f ms (%.3f ms/insert)",
                     repo.count(), seedMs, seedMs / Double(rowCount)))

        measure("list fetch (limit 300)", iterations: 30) {
            _ = repo.fetch(HistoryFilter(limit: 300))
        }
        measure("search: whole token", iterations: 30) {
            _ = repo.fetch(HistoryFilter(query: "lorem", limit: 300))
        }
        measure("search: mid-word substring", iterations: 30) {
            _ = repo.fetch(HistoryFilter(query: "orem", limit: 300))
        }
        measure("search: two terms", iterations: 30) {
            _ = repo.fetch(HistoryFilter(query: "lorem amet", limit: 300))
        }

        var item = ClipItem(kind: .text)
        item.text = "selection sync payload"
        let pb = NSPasteboard(name: NSPasteboard.Name("ClippetBench"))
        measure("pasteboard write (text)", iterations: 50) {
            try? PasteboardWriter.write(item, to: pb)
        }

        let img = NSImage(size: NSSize(width: 1200, height: 800))
        img.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
        img.unlockFocus()
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            var ic = ClassifiedContent(kind: .image)
            ic.data = png
            ic.filename = "Image 1200×800"
            ic.preview = "Image 1200×800"
            ic.byteSize = png.count
            ic.hash = "bench-image"
            let id = repo.insert(ic, sourceApp: "com.apple.Preview", sourceName: "Preview") ?? 0
            ImageStore.dataProvider = { rid in repo.imageData(id: rid) }
            print("\nimage payload: \(png.count / 1024) KB, row id \(id)")
            measure("thumbnail decode (cold)", iterations: 1) {
                ImageStore.purge()
                _ = ImageStore.thumbnail(forID: id)
            }
            measure("thumbnail (cached)", iterations: 200) {
                _ = ImageStore.thumbnail(forID: id)
            }
        }

        let tileArea = NSSize(width: 235, height: 134)
        measure("checkerboard: canvas rects", iterations: 100) {
            let image = NSImage(size: tileArea)
            image.lockFocus()
            NSColor(white: 0.24, alpha: 1).setFill()
            NSRect(origin: .zero, size: tileArea).fill()
            NSColor(white: 0.32, alpha: 1).setFill()
            var row = 0
            var y: CGFloat = 0
            while y < tileArea.height {
                var col = 0
                var x: CGFloat = 0
                while x < tileArea.width {
                    if (row + col) % 2 == 0 { NSRect(x: x, y: y, width: 7, height: 7).fill() }
                    x += 7; col += 1
                }
                y += 7; row += 1
            }
            image.unlockFocus()
        }
        measure("checkerboard: tiled image", iterations: 100) {
            let image = NSImage(size: tileArea)
            image.lockFocus()
            NSColor(patternImage: CheckerTile.image).setFill()
            NSRect(origin: .zero, size: tileArea).fill()
            image.unlockFocus()
        }

        let safariPath = "/Applications/Safari.app"
        measure("file icon: LaunchServices", iterations: 50) {
            _ = NSWorkspace.shared.icon(forFile: safariPath)
        }
        measure("file icon: cached", iterations: 50) {
            _ = ImageStore.fileIcon(forPath: safariPath)
        }

        try? FileManager.default.removeItem(at: tempDir)
        print(String(repeating: "-", count: 52))
    }

    static func runLarge() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippetBig-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let db = try? Database.open(at: dir.appendingPathComponent("big.db")) else {
            print("open failed"); exit(1)
        }
        let repo = Repository(db: db)
        ImageStore.dataProvider = { repo.imageData(id: $0) }
        let pb = NSPasteboard(name: NSPasteboard.Name("ClippetBig"))

        print("Clippet large-payload bench")
        print(String(repeating: "-", count: 56))

        let mb = 20
        let bigText = String(repeating: "lorem ipsum dolor sit amet consectetur adipiscing elit. ", count: mb * 1024 * 1024 / 60)
        print(String(format: "text payload: %.1f MB (%d chars)", Double(bigText.utf8.count) / 1048576, bigText.count))

        measure("classify 20MB text", iterations: 3) {
            pb.clearContents(); pb.setString(bigText, forType: .string)
            _ = ContentClassifier.classify(PasteboardSnapshot.capture(pb) ?? PasteboardSnapshot(types: [], string: nil, pngData: nil, tiffData: nil, fileURLs: [], color: nil))
        }

        var big = ClassifiedContent(kind: .text)
        big.text = bigText
        big.preview = String(bigText.prefix(400))
        big.byteSize = bigText.utf8.count
        big.hash = "big-text"
        measure("insert 20MB text", iterations: 3) {
            _ = repo.insert(big, sourceApp: "com.apple.Safari", sourceName: "Safari")
        }
        measure("list fetch (with 20MB row)", iterations: 10) {
            _ = repo.fetch(HistoryFilter(limit: 300))
        }
        measure("search across 20MB row", iterations: 10) {
            _ = repo.fetch(HistoryFilter(query: "adipiscing", limit: 300))
        }
        measure("pasteboard write 20MB", iterations: 3) {
            try? PasteboardWriter.write(ClipItem(id: 1, kind: .text).withText(bigText), to: pb)
        }

        for dim in [8000, 12000] {
            autoreleasepool {
                guard let png = solidPNG(dim) else { return }
                print(String(format: "\nimage %dx%d -> %.1f MB png", dim, dim, Double(png.count) / 1048576))
                measure("normalize \(dim)px", iterations: 1) {
                    _ = ImageNormalizer.normalize(png)
                }
                var ic = ClassifiedContent(kind: .image)
                ic.data = ImageNormalizer.normalize(png) ?? png
                ic.filename = "big"
                ic.preview = "big"
                ic.byteSize = ic.data!.count
                ic.hash = "big-img-\(dim)"
                let id = repo.insert(ic, sourceApp: "com.apple.Preview", sourceName: "Preview") ?? 0
                measure("thumbnail \(dim)px (cold)", iterations: 1) {
                    ImageStore.purge()
                    _ = ImageStore.thumbnail(forID: id)
                }
                measure("full data read \(dim)px", iterations: 3) {
                    _ = repo.imageData(id: id)
                }
            }
        }

        let paths = (0..<200).map { "\(dir.path)/file-\($0).txt" }
        for p in paths { FileManager.default.createFile(atPath: p, contents: Data("x".utf8)) }
        pb.clearContents()
        pb.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        measure("classify 200 files", iterations: 5) {
            _ = ContentClassifier.classify(PasteboardSnapshot.capture(pb) ?? PasteboardSnapshot(types: [], string: nil, pngData: nil, tiffData: nil, fileURLs: [], color: nil))
        }
        var fc = ClassifiedContent(kind: .file)
        fc.paths = paths
        fc.text = paths.joined(separator: "\n")
        fc.filename = "200 files"
        fc.preview = "200 files"
        fc.byteSize = 200
        fc.hash = "big-files"
        _ = repo.insert(fc, sourceApp: "com.apple.finder", sourceName: "Finder")
        measure("pasteboard write 200 files", iterations: 5) {
            try? PasteboardWriter.write(ClipItem(id: 2, kind: .file).withPaths(paths), to: pb)
        }

        print(String(repeating: "-", count: 56))
        try? FileManager.default.removeItem(at: dir)
        exit(0)
    }

    /// Bulk JSON: many large rows, then query inside them.
    static func runJSON() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippetJSON-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let db = try? Database.open(at: dir.appendingPathComponent("j.db")) else { exit(1) }
        let repo = Repository(db: db)
        print("Clippet bulk-JSON bench")
        print(String(repeating: "-", count: 56))

        // ~2 MB JSON documents, each with a unique deep field.
        func makeJSON(_ i: Int) -> String {
            var body = "{\"id\":\(i),\"items\":["
            for k in 0..<20000 {
                if k > 0 { body += "," }
                body += "{\"k\":\(k),\"v\":\"value_\(i)_\(k)\",\"flag\":\(k % 2 == 0)}"
            }
            body += "],\"needle_REFERENCE\":\"FINDME_\(i)\"}"
            return body
        }
        let count = 50
        let seedStart = DispatchTime.now().uptimeNanoseconds
        for i in 0..<count {
            autoreleasepool {
                var c = ClassifiedContent(kind: .code)
                c.text = makeJSON(i)
                c.preview = "json \(i)"
                c.byteSize = c.text!.utf8.count
                c.hash = "json-\(i)"
                _ = repo.insert(c, sourceApp: "com.apple.Safari", sourceName: "Safari")
            }
        }
        let seedMs = Double(DispatchTime.now().uptimeNanoseconds - seedStart) / 1_000_000
        print(String(format: "%d JSON rows (%.0f MB total) seeded in %.0f ms", count,
                     Double(count * 2) , seedMs))

        measure("search unique deep key", iterations: 5) {
            _ = repo.fetch(HistoryFilter(query: "FINDME_37", limit: 300))
        }
        measure("search common key 'value'", iterations: 5) {
            _ = repo.fetch(HistoryFilter(query: "value_7_", limit: 300))
        }
        measure("search CJK miss", iterations: 5) {
            _ = repo.fetch(HistoryFilter(query: "优化", limit: 300))
        }
        measure("list fetch", iterations: 10) {
            _ = repo.fetch(HistoryFilter(limit: 300))
        }
        print(String(repeating: "-", count: 56))
        try? FileManager.default.removeItem(at: dir)
        exit(0)
    }

    /// End-to-end throughput: pasteboard write -> capture -> classify -> insert ->
    /// read back -> pasteboard write again.
    static func runThroughput() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippetTP-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let db = try? Database.open(at: dir.appendingPathComponent("tp.db")) else { exit(1) }
        let repo = Repository(db: db)
        ImageStore.dataProvider = { repo.imageData(id: $0) }
        PasteboardWriter.textProvider = { repo.fullText(id: $0) }
        let pb = NSPasteboard(name: NSPasteboard.Name("ClippetTP"))

        print("Clippet end-to-end throughput")
        print(String(repeating: "-", count: 60))

        for dim in [3000, 6000, 12000] {
            autoreleasepool {
                guard let png = solidPNG(dim) else { return }
                print(String(format: "\nimage %dx%d  png=%.1f MB (%.1f MP)", dim, dim,
                             Double(png.count) / 1048576, Double(dim * dim) / 1e6))
                // Producer side: the app copying this payload writes it to the pasteboard.
                var t = DispatchTime.now().uptimeNanoseconds
                pb.clearContents(); pb.setData(png, forType: .png)
                print(String(format: "  pasteboard setData        %7.1f ms", ms(since: t)))

                t = DispatchTime.now().uptimeNanoseconds
                let snap = PasteboardSnapshot.capture(pb)
                print(String(format: "  snapshot (read bytes)     %7.1f ms", ms(since: t)))

                t = DispatchTime.now().uptimeNanoseconds
                let content = snap.flatMap { ContentClassifier.classify($0) }
                print(String(format: "  classify + normalise      %7.1f ms", ms(since: t)))

                guard let c = content else { return }
                print(String(format: "  stored payload            %.1f MB (uti %@)", Double((c.data?.count ?? 0)) / 1048576, c.uti ?? "-"))

                t = DispatchTime.now().uptimeNanoseconds
                let id = repo.insert(c, sourceApp: "com.apple.Preview", sourceName: "Preview") ?? 0
                print(String(format: "  insert                    %7.1f ms", ms(since: t)))

                t = DispatchTime.now().uptimeNanoseconds
                _ = ImageStore.thumbnail(forID: id)
                print(String(format: "  thumbnail (cold)          %7.1f ms", ms(since: t)))

                t = DispatchTime.now().uptimeNanoseconds
                let item = repo.item(id: id) ?? ClipItem(kind: .image)
                try? PasteboardWriter.write(item, to: pb)
                print(String(format: "  paste (read + setData)    %7.1f ms", ms(since: t)))

                ImageStore.purge()
            }
        }

        let big = String(repeating: "lorem ipsum dolor sit amet ", count: 400_000)  // ~10 MB
        print(String(format: "\ntext payload %.1f MB", Double(big.utf8.count) / 1048576))
        var t = DispatchTime.now().uptimeNanoseconds
        pb.clearContents(); pb.setString(big, forType: .string)
        print(String(format: "  pasteboard setString      %7.1f ms", ms(since: t)))
        t = DispatchTime.now().uptimeNanoseconds
        let tsnap = PasteboardSnapshot.capture(pb)
        print(String(format: "  snapshot                  %7.1f ms", ms(since: t)))
        t = DispatchTime.now().uptimeNanoseconds
        let tc = tsnap.flatMap { ContentClassifier.classify($0) }
        print(String(format: "  classify                  %7.1f ms", ms(since: t)))
        if let tc = tc {
            t = DispatchTime.now().uptimeNanoseconds
            let id = repo.insert(tc, sourceApp: "com.apple.Safari", sourceName: "Safari") ?? 0
            print(String(format: "  insert                    %7.1f ms", ms(since: t)))
            t = DispatchTime.now().uptimeNanoseconds
            if let item = repo.item(id: id) { try? PasteboardWriter.write(item, to: pb) }
            print(String(format: "  paste back                %7.1f ms", ms(since: t)))
        }
        print(String(repeating: "-", count: 60))
        try? FileManager.default.removeItem(at: dir)
        exit(0)
    }

    private static func ms(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func solidPNG(_ dim: Int) -> Data? {
        guard let ctx = CGContext(data: nil, width: dim, height: dim, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let _ = Optional(ctx) else { return nil }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: dim, height: dim))
        guard let cg = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData,
                                                          "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private static func measure(_ label: String, iterations: Int, _ block: () -> Void) {

        block()
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { block() }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let per = elapsed / Double(iterations)
        print(String(format: "  %@ %8.3f ms/op  (%d iters)", label.padding(toLength: 30, withPad: " ", startingAt: 0) as NSString, per, iterations))
    }
}

#endif
