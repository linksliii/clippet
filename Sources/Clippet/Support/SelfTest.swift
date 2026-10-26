#if DEBUG
import AppKit

enum SelfTest {

    private static var failures = 0

    static func run() {
        print("Clippet selftest")
        print(String(repeating: "-", count: 46))

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClippetSelfTest"))
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippetSelfTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let db = try? Database.open(at: tempDir.appendingPathComponent("test.db")) else {
            print("FAIL: could not open test database")
            exit(1)
        }
        let repo = Repository(db: db)

        expect(classify(pasteboard, text: "hello world")?.kind == .text, "plain text → .text")
        expect(classify(pasteboard, text: "https://example.com/path?a=1")?.kind == .link, "url → .link")
        expect(classify(pasteboard, text: "#FF8800")?.kind == .color, "hex → .color")
        expect(classify(pasteboard, text: "func main() {\n  return 1;\n}")?.kind == .code, "code → .code")
        expect(classify(pasteboard, text: "   \n  ") == nil, "blank text is skipped")

        let secret = classify(pasteboard, text: "aws AKIAIOSFODNN7EXAMPLE key")
        expect(secret?.tags.contains("secret") == true, "aws key tagged secret")
        let pem = classify(pasteboard, text: "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----")
        expect(pem?.tags.contains("private-key") == true, "PEM tagged private-key")
        let email = classify(pasteboard, text: "reach me at dev@example.com")
        expect(email?.tags.contains("email") == true, "email detected")

        var textItem = ClipItem(kind: .text)
        textItem.text = "round trip"
        try? PasteboardWriter.write(textItem, to: pasteboard)
        expect(pasteboard.string(forType: .string) == "round trip", "text writes to pasteboard")

        var linkItem = ClipItem(kind: .link)
        linkItem.text = "https://example.com/page"
        try? PasteboardWriter.write(linkItem, to: pasteboard)
        expect(pasteboard.string(forType: .string) == "https://example.com/page", "link writes to pasteboard")

        var colorItem = ClipItem(kind: .color)
        colorItem.text = "#FF8800"
        try? PasteboardWriter.write(colorItem, to: pasteboard)
        let roundTrippedColor = pasteboard.readObjects(forClasses: [NSColor.self], options: nil)?.first as? NSColor
        expect(roundTrippedColor?.hexString == "#FF8800", "color round-trips through the pasteboard")

        let png = makePNG()
        var imageItem = ClipItem(kind: .image)
        imageItem.data = png
        try? PasteboardWriter.write(imageItem, to: pasteboard)
        expect(pasteboard.data(forType: .png)?.count == png.count, "image writes to pasteboard")

        let fileURL = tempDir.appendingPathComponent("roundtrip.txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))
        var fileItem = ClipItem(kind: .file)
        fileItem.paths = [fileURL.path]
        try? PasteboardWriter.write(fileItem, to: pasteboard)
        let writtenURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL]
        expect(writtenURLs?.first?.path == fileURL.path, "file writes to pasteboard")

        guard let firstID = insert(repo, pasteboard, "alpha beta"),
              let secondID = insert(repo, pasteboard, "gamma delta") else {
            print("FAIL: insert returned nil")
            exit(1)
        }
        expect(repo.count() == 2, "two rows stored")

        _ = insert(repo, pasteboard, "alpha beta")
        expect(repo.count() == 2, "duplicate copy does not add a row")
        expect(repo.recent(limit: 1).first?.id == firstID, "duplicate bumped to top")

        expect(repo.fetch(HistoryFilter(query: "gamma")).count == 1, "search finds a whole token")
        expect(repo.fetch(HistoryFilter(query: "gam")).count == 1, "search finds a prefix")
        expect(repo.fetch(HistoryFilter(query: "lph")).count == 1, "search finds a mid-word substring")
        expect(repo.fetch(HistoryFilter(query: "zzzz")).isEmpty, "search miss returns nothing")

        _ = insert(repo, pasteboard, "全站最详细的二合一笔记本优化教程")
        expect(repo.fetch(HistoryFilter(query: "优化")).count == 1,
               "search finds a CJK fragment at the end of a sentence")
        expect(repo.fetch(HistoryFilter(query: "笔记本")).count == 1,
               "search finds a CJK fragment mid-sentence")

        expect(repo.fetch(HistoryFilter(query: "gamma delta")).count == 1,
               "multi-term search ANDs the terms")
        expect(repo.fetch(HistoryFilter(query: "gamma zzzz")).isEmpty,
               "multi-term search requires every term")

        expect(!repo.fetch(HistoryFilter(query: "TestApp")).isEmpty,
               "source app name is searchable")

        _ = insert(repo, pasteboard, "zzz alpha appears late")
        let ranked = repo.fetch(HistoryFilter(query: "alpha"))
        expect(ranked.first?.text == "alpha beta",
               "prefix match outranks a mid-string match")

        let boardA = repo.defaultBoard().id
        let boardB = repo.createBoard(name: "Search Board")
        var other = ClassifiedContent(kind: .text)
        other.text = "orphan needle in another board"
        other.preview = other.text!
        other.byteSize = other.text!.utf8.count
        other.hash = "search-board-item"
        _ = repo.insert(other, sourceApp: "com.test.app", sourceName: "TestApp", boardID: boardB)
        expect(repo.fetch(HistoryFilter(query: "needle", boardID: boardA)).count == 1,
               "search reaches items in other pinboards")
        expect(repo.fetch(HistoryFilter(boardID: boardA)).contains { $0.text?.contains("needle") == true } == false,
               "browsing stays scoped to its pinboard")

        repo.setPinned(secondID, true)
        expect(repo.fetch(HistoryFilter(pinnedOnly: true)).count == 1, "pinned filter")
        repo.setSnippet(firstID, true)
        expect(repo.fetch(HistoryFilter(snippetsOnly: true)).count == 1, "snippet filter")

        for i in 0..<20 { _ = insert(repo, pasteboard, "filler \(i)") }
        repo.trim(capacity: 5)
        let remaining = repo.count()

        expect(remaining == 7, "trim keeps 5 recent + pin + snippet (got \(remaining))")
        expect(repo.fetch(HistoryFilter(pinnedOnly: true)).count == 1, "pin survives trim")
        expect(repo.fetch(HistoryFilter(snippetsOnly: true)).count == 1, "snippet survives trim")

        repo.delete(id: secondID)
        expect(repo.fetch(HistoryFilter(pinnedOnly: true)).isEmpty, "delete removes pinned row")

        _ = insert(repo, pasteboard, "func main() {\n  return 1;\n}")
        let textFiltered = repo.fetch(HistoryFilter(kind: .text))
        expect(textFiltered.contains { $0.kind == .code }, "Text filter includes code clips")
        let codeStored = repo.fetch(HistoryFilter(limit: 500)).contains { $0.kind == .code }
        expect(codeStored, "code content is classified as .code")

        let futureFilter = HistoryFilter(since: Date().addingTimeInterval(3600))
        expect(repo.fetch(futureFilter).isEmpty, "date filter excludes older clips")
        let pastFilter = HistoryFilter(since: Date().addingTimeInterval(-3600))
        expect(!repo.fetch(pastFilter).isEmpty, "date filter keeps recent clips")
        let appFiltered = repo.fetch(HistoryFilter(sourceApp: "com.test.app"))
        expect(!appFiltered.isEmpty, "app filter matches the seeded source app")

        let vm = ClipboardViewModel(repo: repo)
        vm.reload(resetSelection: true)
        let visible = vm.items
        expect(visible.count >= 3, "enough rows for multi-select checks")
        if let first = visible.first, let second = visible.dropFirst().first {
            vm.toggleSelection(first)
            expect(vm.hasMultiSelection && vm.selectedIDs.count == 1, "cmd-click adds to selection")
            vm.toggleSelection(first)
            expect(!vm.hasMultiSelection, "cmd-click again removes it")
            vm.selection = 0
            vm.selectRange(to: 2)
            expect(vm.selectedIDs.count == 3, "shift-click selects the range")
            vm.clearMultiSelection()
            expect(!vm.hasMultiSelection, "deselect all clears the set")
            vm.selectAllVisible()
            expect(vm.selectedIDs.count == visible.count, "select all covers every visible row")
            _ = second
            let before = repo.count()
            vm.deleteSelected()
            expect(repo.count() == before - Int64(visible.count), "delete removes the whole selection")
        }

        for i in 0..<4 { _ = insert(repo, pasteboard, "hit test row \(i)") }
        let hitVM = ClipboardViewModel(repo: repo)
        hitVM.reload(resetSelection: true)

        hitVM.cardFrames = [
            0: CGRect(x: 24, y: 78, width: 235, height: 214),
            1: CGRect(x: 288, y: 78, width: 235, height: 214)
        ]
        expect(hitVM.cardIndex(at: CGPoint(x: 100, y: 150)) == 0, "hit test resolves the first card")
        expect(hitVM.cardIndex(at: CGPoint(x: 300, y: 150)) == 1, "hit test resolves the second card")
        expect(hitVM.cardIndex(at: CGPoint(x: 270, y: 150)) == nil, "hit test ignores the gap between cards")
        expect(hitVM.cardIndex(at: CGPoint(x: 100, y: 20)) == nil, "hit test ignores the toolbar area")

        hitVM.handleClick(index: 1, clickCount: 1, modifiers: [])
        expect(hitVM.selection == 1, "plain click selects the card")
        hitVM.handleClick(index: 0, clickCount: 1, modifiers: .command)
        expect(hitVM.selectedIDs.contains(hitVM.items[0].id), "cmd-click toggles multi-selection")
        hitVM.handleClick(index: 1, clickCount: 1, modifiers: .shift)
        expect(hitVM.selectedIDs.count >= 2, "shift-click extends the range")

        let browsing = KeyContext(previewOpen: false, filtersOpen: false, boardCount: 2)
        expect(KeyRouter.resolve(keyCode: 0, modifiers: [], characters: "a",
                                 context: browsing) == .passThrough,
               "plain letters fall through to the input field")

        expect(KeyRouter.resolve(keyCode: 0, modifiers: .control, characters: "a",
                                 context: browsing) == .selectAllText,
               "ctrl+A selects the query text")
        var emptyField = browsing
        expect(KeyRouter.resolve(keyCode: 0, modifiers: .command, characters: "a",
                                 context: emptyField) == .selectAllCards,
               "cmd+A with an empty field selects all cards")
        emptyField.queryEmpty = false
        expect(KeyRouter.resolve(keyCode: 0, modifiers: .command, characters: "a",
                                 context: emptyField) == .selectAllText,
               "cmd+A with text selects the query")
        expect(KeyRouter.resolve(keyCode: 3, modifiers: .command, characters: "f",
                                 context: browsing) == .beginSearch,
               "cmd+F focuses search")
        expect(KeyRouter.resolve(keyCode: 16, modifiers: .command, characters: "y",
                                 context: browsing) == .preview,
               "cmd+Y opens the preview")

        expect(KeyRouter.resolve(keyCode: 124, modifiers: .command, characters: nil,
                                 context: browsing) == .switchBoard(1),
               "cmd+right switches to the next pinboard")
        expect(KeyRouter.resolve(keyCode: 123, modifiers: .command, characters: nil,
                                 context: browsing) == .switchBoard(-1),
               "cmd+left switches to the previous pinboard")

        expect(KeyRouter.resolve(keyCode: 18, modifiers: .command, characters: "1",
                                 context: browsing) == .quickPaste(1),
               "cmd+1 quick-pastes the first card")
        expect(KeyRouter.resolve(keyCode: 28, modifiers: .command, characters: "9",
                                 context: browsing) == .quickPaste(9),
               "cmd+9 quick-pastes the ninth card")
        expect(KeyRouter.resolve(keyCode: 19, modifiers: [], characters: "2",
                                 context: browsing) == .passThrough,
               "a bare digit still types (IME safe)")

        var previewing = browsing
        previewing.previewOpen = true
        expect(KeyRouter.resolve(keyCode: 53, modifiers: [], characters: nil,
                                 context: previewing) == .closePreview,
               "esc closes the preview")

        var withFilters = browsing
        withFilters.filtersOpen = true
        expect(KeyRouter.resolve(keyCode: 53, modifiers: [], characters: nil,
                                 context: withFilters) == .closeFilters,
               "esc closes the filter popover first")

        func space(composing: Bool = false, preview: Bool = false, filters: Bool = false,
                   queryEmpty: Bool = true, navigating: Bool = false,
                   selection: Bool = true) -> Bool {
            SpaceRouter.shouldPreview(isComposing: composing, previewOpen: preview,
                                      filtersOpen: filters, queryEmpty: queryEmpty,
                                      isNavigating: navigating, hasSelection: selection)
        }
        expect(space(), "space previews when browsing an empty query")
        expect(!space(composing: true), "space goes to the IME while composing")
        expect(!space(queryEmpty: false), "space types a space while typing a query")
        expect(space(queryEmpty: false, navigating: true),
               "space previews again once the user navigates results")
        expect(!space(selection: false), "space does nothing with no selection")
        expect(!space(preview: true), "space does not re-open an open preview")
        expect(!space(filters: true), "space does not fire behind the filter popover")

        try? FileManager.default.removeItem(at: tempDir)

        print(String(repeating: "-", count: 46))
        if failures == 0 {
            print("all checks passed")
            exit(0)
        } else {
            print("\(failures) check(s) failed")
            exit(1)
        }
    }

    private static func classify(_ pb: NSPasteboard, text: String) -> ClassifiedContent? {
        pb.clearContents()
        pb.setString(text, forType: .string)
        return ContentClassifier.classify(PasteboardSnapshot.capture(pb) ?? PasteboardSnapshot(types: [], string: nil, pngData: nil, tiffData: nil, fileURLs: [], color: nil))
    }

    private static func insert(_ repo: Repository, _ pb: NSPasteboard, _ text: String) -> Int64? {
        pb.clearContents()
        pb.setString(text, forType: .string)
        guard let content = ContentClassifier.classify(PasteboardSnapshot.capture(pb) ?? PasteboardSnapshot(types: [], string: nil, pngData: nil, tiffData: nil, fileURLs: [], color: nil)) else { return nil }
        return repo.insert(content, sourceApp: "com.test.app", sourceName: "TestApp")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("  ok   \(label)")
        } else {
            print("  FAIL \(label)")
            failures += 1
        }
    }

    private static func makePNG() -> Data {
        let size = CGSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}

#endif
