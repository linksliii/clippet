import Foundation

struct HistoryFilter {
    var query: String = ""
    var kind: ClipKind?
    var sourceApp: String?
    var boardID: Int64?

    var since: Date?
    var pinnedOnly: Bool = false
    var snippetsOnly: Bool = false
    var limit: Int = 200
}

final class Repository {
    private let db: Database

    private static let listColumns = """
    i.id, i.board_id, i.kind, i.preview AS text, i.paths, i.filename, i.uti, i.preview,
    i.tags, i.source_app, i.source_name, i.source_tint, i.link_title,
    i.created_at, i.is_pinned, i.is_snippet, i.stack_order, i.byte_size, i.hash
    """

    init(db: Database) {
        self.db = db
    }

    @discardableResult
    func insert(_ c: ClassifiedContent,
                sourceApp: String?,
                sourceName: String?,
                sourceTint: String? = nil,
                boardID: Int64 = 0) -> Int64? {
        let now = Date().timeIntervalSince1970

        if let existing = (try? db.query(
            "SELECT id FROM items WHERE hash = ? LIMIT 1", [.text(c.hash)]
        ))?.first, let id = existing["id"] as? Int64 {
            try? db.run("UPDATE items SET created_at = ? WHERE id = ?", [.double(now), .int(id)])
            return id
        }

        do {
            let id = try db.run("""
            INSERT INTO items
              (kind, text, data, paths, filename, uti, preview, tags, source_app,
               source_name, source_tint, board_id, created_at, is_pinned, is_snippet,
               stack_order, byte_size, hash)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,0,0,NULL,?,?)
            """, [
                .text(c.kind.rawValue),
                .opt(c.text),
                .opt(c.data),
                .opt(c.paths.isEmpty ? nil : c.paths.joined(separator: "\n")),
                .opt(c.filename),
                .opt(c.uti),
                .text(c.preview),
                .text(c.tags.joined(separator: ",")),
                .opt(sourceApp),
                .opt(sourceName),
                .opt(sourceTint),
                .int(boardID == 0 ? defaultBoard().id : boardID),
                .double(now),
                .int(Int64(c.byteSize)),
                .text(c.hash)
            ])
            if let app = sourceApp {
                recordApp(app, name: sourceName, at: now)
            }
            return id
        } catch {
            NSLog("Clippet: insert failed: \(error)")
            return nil
        }
    }

    private func recordApp(_ bundleID: String, name: String?, at time: TimeInterval) {
        try? db.run("""
        INSERT INTO app_usage (bundle_id, name, clip_count, last_seen)
        VALUES (?,?,1,?)
        ON CONFLICT(bundle_id) DO UPDATE SET
            clip_count = clip_count + 1,
            name = COALESCE(excluded.name, name),
            last_seen = excluded.last_seen
        """, [.text(bundleID), .opt(name), .double(time)])
    }

    func fetch(_ filter: HistoryFilter) -> [ClipItem] {
        var clauses: [String] = []
        var params: [SQLValue] = []

        if filter.pinnedOnly { clauses.append("i.is_pinned = 1") }
        if filter.snippetsOnly { clauses.append("i.is_snippet = 1") }
        if let board = filter.boardID {
            clauses.append("i.board_id = ?")
            params.append(.int(board))
        }
        if let since = filter.since {
            clauses.append("i.created_at >= ?")
            params.append(.double(since.timeIntervalSince1970))
        }
        if let kind = filter.kind {
            if kind == .text {

                clauses.append("i.kind IN ('text','code')")
            } else {
                clauses.append("i.kind = ?")
                params.append(.text(kind.rawValue))
            }
        }
        if let app = filter.sourceApp {
            clauses.append("i.source_app = ?")
            params.append(.text(app))
        }

        let trimmed = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return search(trimmed, filter: filter)
        }
        var sql = "SELECT \(Repository.listColumns) FROM items i"
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY i.is_pinned DESC, i.created_at DESC LIMIT \(filter.limit)"
        return db.queryMapped(sql, params) { Repository.mapItem($0) }
    }

    func item(id: Int64) -> ClipItem? {
        db.queryMapped("SELECT \(Repository.listColumns) FROM items i WHERE i.id = ?",
                       [.int(id)]) { Repository.mapItem($0) }.first
    }

    /// Full text for one row; list queries carry only the first 600 chars.
    func fullText(id: Int64) -> String? {
        (try? db.query("SELECT text FROM items WHERE id = ?", [.int(id)]))?
            .first?["text"] as? String
    }

    func imageData(id: Int64) -> Data? {
        (try? db.query("SELECT data FROM items WHERE id = ?", [.int(id)]))?
            .first?["data"] as? Data
    }

    func recent(limit: Int) -> [ClipItem] {
        fetch(HistoryFilter(limit: limit))
    }

    func apps() -> [(bundleID: String, name: String, count: Int64)] {
        let rows = (try? db.query("""
        SELECT bundle_id, name, clip_count FROM app_usage ORDER BY clip_count DESC
        """)) ?? []
        return rows.compactMap { r in
            guard let id = r["bundle_id"] as? String else { return nil }
            return (id, (r["name"] as? String) ?? id, (r["clip_count"] as? Int64) ?? 0)
        }
    }

    func setPinned(_ id: Int64, _ pinned: Bool) {
        try? db.run("UPDATE items SET is_pinned = ? WHERE id = ?", [.bool(pinned), .int(id)])
    }

    func setSnippet(_ id: Int64, _ snippet: Bool) {
        try? db.run("UPDATE items SET is_snippet = ? WHERE id = ?", [.bool(snippet), .int(id)])
    }

    func setCreatedAt(id: Int64, _ when: TimeInterval) {
        try? db.run("UPDATE items SET created_at = ? WHERE id = ?", [.double(when), .int(id)])
    }

    func delete(id: Int64) {
        try? db.run("DELETE FROM items WHERE id = ?", [.int(id)])
    }

    func clearHistory() {
        try? db.run("DELETE FROM items WHERE is_pinned = 0 AND is_snippet = 0")
        try? db.run("VACUUM")
    }

    func trim(capacity: Int) {
        guard capacity > 0 else { return }
        try? db.run("""
        DELETE FROM items WHERE id IN (
            SELECT id FROM items
            WHERE is_pinned = 0 AND is_snippet = 0
            ORDER BY created_at DESC
            LIMIT -1 OFFSET ?
        )
        """, [.int(Int64(capacity))])
    }

    func deleteOlderThan(_ date: Date) {
        try? db.run("""
        DELETE FROM items
         WHERE created_at < ? AND is_pinned = 0 AND is_snippet = 0
        """, [.double(date.timeIntervalSince1970)])
    }

    func count() -> Int64 {
        (try? db.scalar("SELECT COUNT(*) FROM items")) ?? 0
    }

    private static func mapItem(_ r: Row) -> ClipItem {
        var item = ClipItem(id: r.int("id"),
                            kind: ClipKind(rawValue: r.string("kind") ?? "text") ?? .text)
        item.boardID = r.int("board_id")
        item.text = r.string("text")
        if let p = r.string("paths"), !p.isEmpty {
            item.paths = p.components(separatedBy: "\n")
        }
        item.filename = r.string("filename")
        item.uti = r.string("uti")
        item.preview = r.string("preview") ?? ""
        if let t = r.string("tags"), !t.isEmpty {
            item.tags = t.components(separatedBy: ",")
        }
        item.sourceApp = r.string("source_app")
        item.sourceAppName = r.string("source_name")
        item.sourceTint = r.string("source_tint")
        item.linkTitle = r.string("link_title")
        item.createdAt = Date(timeIntervalSince1970: r.double("created_at"))
        item.isPinned = r.bool("is_pinned")
        item.isSnippet = r.bool("is_snippet")
        if let so = r.optInt("stack_order") { item.stackOrder = Int(so) }
        item.byteSize = Int(r.int("byte_size"))
        item.hash = r.string("hash") ?? ""
        return item
    }

    func search(_ query: String, filter: HistoryFilter) -> [ClipItem] {
        let terms = Repository.searchTerms(query)
        guard !terms.isEmpty else { return [] }
        var clauses: [String] = []
        var params: [SQLValue] = []

        if let since = filter.since {
            clauses.append("i.created_at >= ?")
            params.append(.double(since.timeIntervalSince1970))
        }
        if let kind = filter.kind {
            if kind == .text {
                clauses.append("i.kind IN ('text','code')")
            } else {
                clauses.append("i.kind = ?")
                params.append(.text(kind.rawValue))
            }
        }
        if let app = filter.sourceApp {
            clauses.append("i.source_app = ?")
            params.append(.text(app))
        }

        var termClauses: [String] = []
        for term in terms {
            let pattern = "%" + Repository.escapeLike(term) + "%"
            termClauses.append("""
            (COALESCE(i.text,'') LIKE ? ESCAPE '\\' \
             OR COALESCE(i.preview,'') LIKE ? ESCAPE '\\' \
             OR COALESCE(i.filename,'') LIKE ? ESCAPE '\\' \
             OR COALESCE(i.source_name,'') LIKE ? ESCAPE '\\' \
             OR COALESCE(i.paths,'') LIKE ? ESCAPE '\\' \
             OR COALESCE(i.link_title,'') LIKE ? ESCAPE '\\')
            """)
            for _ in 0..<6 { params.append(.text(pattern)) }
        }
        clauses.append("(" + termClauses.joined(separator: " AND ") + ")")

        var sql = "SELECT \(Repository.listColumns) FROM items i"
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }

        sql += " ORDER BY i.created_at DESC LIMIT \(max(filter.limit, 300))"

        let items = db.queryMapped(sql, params) { Repository.mapItem($0) }

        var scored: [(item: ClipItem, score: Int)] = []
        scored.reserveCapacity(items.count)
        for item in items {
            scored.append((item, Repository.relevance(item, terms: terms)))
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.item.createdAt > rhs.item.createdAt
        }
        return scored.prefix(filter.limit).map(\.item)
    }

    static func searchTerms(_ query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { $0 }
    }

    private static func escapeLike(_ term: String) -> String {
        term
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    static func relevance(_ item: ClipItem, terms: [String]) -> Int {

        let primary = String((item.text ?? item.filename ?? item.preview).prefix(400))
        let app = item.sourceAppName ?? ""

        var total = 0
        for term in terms {

            if let found = primary.range(of: term, options: .caseInsensitive) {
                if found.lowerBound == primary.startIndex {
                    total += found.upperBound == primary.endIndex ? 120 : 70
                } else {
                    let before = primary[primary.index(before: found.lowerBound)]
                    total += (before.isWhitespace || before.isNewline) ? 45 : 25
                }
            }
            if !app.isEmpty, app.range(of: term, options: .caseInsensitive) != nil { total += 30 }
        }
        if item.isPinned { total += 15 }
        if item.isSnippet { total += 10 }
        return total
    }

    func boards() -> [Board] {
        let rows = (try? db.query("SELECT * FROM boards ORDER BY sort, id")) ?? []
        return rows.compactMap { r in
            guard let id = r["id"] as? Int64, let name = r["name"] as? String else { return nil }
            return Board(id: id,
                         name: name,
                         tint: (r["tint"] as? String) ?? Board.palette[5],
                         sort: Int((r["sort"] as? Int64) ?? 0),
                         isDefault: ((r["is_default"] as? Int64) ?? 0) != 0)
        }
    }

    @discardableResult
    func createBoard(name: String, tint: String? = nil) -> Int64 {
        let existing = boards()
        let color = tint ?? Board.palette[existing.count % Board.palette.count]
        let maxSort = existing.map(\.sort).max() ?? 0
        return (try? db.run("""
        INSERT INTO boards (name, tint, sort, is_default, created_at) VALUES (?,?,?,0,?)
        """, [.text(name), .text(color), .int(Int64(maxSort + 1)),
              .double(Date().timeIntervalSince1970)])) ?? 0
    }

    func renameBoard(_ id: Int64, name: String) {
        try? db.run("UPDATE boards SET name = ? WHERE id = ?", [.text(name), .int(id)])
    }

    func deleteBoard(_ id: Int64) {
        try? db.run("DELETE FROM items WHERE board_id = ?", [.int(id)])
        try? db.run("DELETE FROM boards WHERE id = ? AND is_default = 0", [.int(id)])
    }

    func moveToBoard(_ itemID: Int64, boardID: Int64) {
        try? db.run("UPDATE items SET board_id = ? WHERE id = ?",
                    [.int(boardID), .int(itemID)])
    }

    func board(id: Int64) -> Board? {
        boards().first { $0.id == id }
    }

    func defaultBoard() -> Board {
        if let existing = boards().first(where: { $0.isDefault }) { return existing }
        if let first = boards().first { return first }
        let id = createBoard(name: "Clipboard", tint: Board.palette[5])
        return Board(id: id, name: "Clipboard", tint: Board.palette[5], isDefault: true)
    }
}
