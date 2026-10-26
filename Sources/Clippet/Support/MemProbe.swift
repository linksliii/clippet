#if DEBUG
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum MemProbe {

    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    private static var last: Double = 0

    private static func checkpoint(_ label: String) {
        let now = residentMB()
        let delta = now - last
        print(String(format: "  %@ %8.1f MB   (%+.1f)", label.padding(toLength: 34, withPad: " ", startingAt: 0) as NSString, now, delta))
        last = now
    }

    static func run() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippetMem-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        guard let db = try? Database.open(at: tempDir.appendingPathComponent("mem.db")) else {
            print("memprobe: db open failed"); exit(1)
        }
        let repo = Repository(db: db)
        ImageStore.dataProvider = { repo.imageData(id: $0) }

        print("Clippet memory probe")
        print(String(repeating: "-", count: 56))
        checkpoint("baseline")

        let body = String(repeating: "lorem ipsum dolor sit amet ", count: 12)
        for i in 0..<2000 {
            var c = ClassifiedContent(kind: .text)
            c.text = "\(body) row \(i)"
            c.preview = c.text!
            c.byteSize = c.text!.utf8.count
            c.hash = "mem-\(i)"
            _ = repo.insert(c, sourceApp: "com.apple.Safari", sourceName: "Safari")
        }
        checkpoint("after 2000 text inserts")

        let ids = seedImages(repo)
        checkpoint("after \(ids.count) image inserts")

        for _ in 0..<50 { _ = repo.fetch(HistoryFilter(limit: 300)) }
        checkpoint("after 50 list fetches")

        for _ in 0..<100 { _ = repo.fetch(HistoryFilter(query: "lorem", limit: 300)) }
        checkpoint("after 100 searches")

        for id in ids { _ = ImageStore.thumbnail(forID: id) }
        checkpoint("after loading all thumbnails")

        for id in ids.prefix(4) { _ = ImageStore.fullData(forID: id) }
        checkpoint("after 4 full-size reads")

        for _ in 0..<5 {
            for id in ids { _ = ImageStore.thumbnail(forID: id) }
        }
        checkpoint("after 5x thumbnail churn")

        let stressStart = residentMB()
        var peak = stressStart
        for round in 0..<300 {
            autoreleasepool {

                var c = ClassifiedContent(kind: .text)
                c.text = "stress \(round) " + String(repeating: "x", count: 200)
                c.preview = c.text!
                c.byteSize = c.text!.utf8.count
                c.hash = "stress-\(round)"
                _ = repo.insert(c, sourceApp: "com.apple.Safari", sourceName: "Safari")

                _ = repo.fetch(HistoryFilter(query: "stress \(round)", limit: 300))

                for id in ids { _ = ImageStore.thumbnail(forID: id) }

                if let first = repo.recent(limit: 1).first {
                    repo.setPinned(first.id, true)
                    repo.setPinned(first.id, false)
                    repo.delete(id: first.id)
                }
                repo.trim(capacity: 300)
            }
            let now = residentMB()
            peak = max(peak, now)
            if round % 100 == 99 {
                print(String(format: "    stress round %3d  rss=%.1f MB", round + 1, now))
            }
        }
        checkpoint("after 300 mixed rounds (peak \(String(format: "%.0f", peak)) MB)")

        ImageStore.purge()
        checkpoint("after purge")

        print(String(repeating: "-", count: 56))
        print("db size: \(dbSizeString(tempDir))")
        try? FileManager.default.removeItem(at: tempDir)
        exit(0)
    }

    private static func seedImages(_ repo: Repository) -> [Int64] {
        var ids: [Int64] = []
        let sizes: [(Int, Int)] = [(200, 200), (800, 600), (1600, 1200), (3000, 2000), (6000, 4000)]
        for (index, size) in sizes.enumerated() {

            autoreleasepool {
                let before = residentMB()
                guard let png = makePNG(size) else { return }
                let afterCreate = residentMB()
                var c = ClassifiedContent(kind: .image)
                c.data = png
                c.filename = "Image \(size.0)×\(size.1)"
                c.preview = c.filename!
                c.byteSize = png.count
                c.hash = "mem-img-\(index)"
                if let id = repo.insert(c, sourceApp: "com.apple.Preview", sourceName: "Preview") {
                    ids.append(id)
                }
                let afterInsert = residentMB()
                print(String(format: "    image %6dx%-5d png=%5.1fMB  create=%+7.1f  insert=%+7.1f  now=%.1f",
                             size.0, size.1, Double(png.count) / 1024 / 1024,
                             afterCreate - before, afterInsert - afterCreate, afterInsert))
            }
        }
        return ids
    }

    private static func makePNG(_ size: (Int, Int)) -> Data? {
        guard let ctx = CGContext(data: nil,
                                  width: size.0, height: size.1,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.0, height: size.1))
        guard let cg = ctx.makeImage() else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return output as Data
    }

    private static func dbSizeString(_ dir: URL) -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let total = files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return String(format: "%.1f MB", Double(total) / 1024 / 1024)
    }
}

#endif
