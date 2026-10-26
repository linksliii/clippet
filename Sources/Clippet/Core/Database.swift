import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DBError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)

    var description: String {
        switch self {
        case .open(let m): return "SQLite open failed: \(m)"
        case .prepare(let m): return "SQLite prepare failed: \(m)"
        case .step(let m): return "SQLite step failed: \(m)"
        }
    }
}

enum SQLValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    static func opt(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }
    static func opt(_ d: Double?) -> SQLValue { d.map { .double($0) } ?? .null }
    static func opt(_ i: Int?) -> SQLValue { i.map { .int(Int64($0)) } ?? .null }
    static func opt(_ b: Data?) -> SQLValue { b.map { .blob($0) } ?? .null }
    static func bool(_ b: Bool) -> SQLValue { .int(b ? 1 : 0) }
}

struct Row {
    private let columns: [String: Int]
    private let stmt: OpaquePointer

    init(stmt: OpaquePointer, columns: [String: Int]) {
        self.stmt = stmt
        self.columns = columns
    }

    private func idx(_ name: String) -> Int32? {
        columns[name].map { Int32($0) }
    }

    func int(_ name: String) -> Int64 {
        guard let i = idx(name) else { return 0 }
        return sqlite3_column_int64(stmt, i)
    }

    func optInt(_ name: String) -> Int64? {
        guard let i = idx(name) else { return nil }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, i)
    }

    func double(_ name: String) -> Double {
        guard let i = idx(name) else { return 0 }
        return sqlite3_column_double(stmt, i)
    }

    func string(_ name: String) -> String? {
        guard let i = idx(name), sqlite3_column_type(stmt, i) != SQLITE_NULL else { return nil }
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }

    func data(_ name: String) -> Data? {
        guard let i = idx(name), sqlite3_column_type(stmt, i) != SQLITE_NULL else { return nil }
        guard let b = sqlite3_column_blob(stmt, i) else { return nil }
        let n = Int(sqlite3_column_bytes(stmt, i))
        return Data(bytes: b, count: n)
    }

    func bool(_ name: String) -> Bool { int(name) != 0 }
}

final class Database {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    static func open(at url: URL) throws -> Database {
        let db = try Database(path: url.path)
        try db.migrate()
        return db
    }

    init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DBError.open(msg)
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
    }

    deinit {
        if let h = handle { sqlite3_close(h) }
    }

    private var errmsg: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }

    func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            throw DBError.step(errmsg)
        }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw DBError.prepare(errmsg)
        }
        for (i, p) in params.enumerated() {
            let position = Int32(i + 1)
            switch p {
            case .null: sqlite3_bind_null(s, position)
            case .int(let v): sqlite3_bind_int64(s, position, v)
            case .double(let v): sqlite3_bind_double(s, position, v)
            case .text(let v): sqlite3_bind_text(s, position, v, -1, SQLITE_TRANSIENT)
            case .blob(let d):
                _ = d.withUnsafeBytes { buf in
                    sqlite3_bind_blob(s, position, buf.baseAddress, Int32(d.count), SQLITE_TRANSIENT)
                }
            }
        }
        return s
    }

    private func columnIndexes(_ stmt: OpaquePointer) -> [String: Int] {
        var map: [String: Int] = [:]
        for i in 0..<sqlite3_column_count(stmt) {
            if let name = sqlite3_column_name(stmt, i) {
                map[String(cString: name)] = Int(i)
            }
        }
        return map
    }

    @discardableResult
    func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let cols = columnIndexes(stmt)
        var out: [[String: Any]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            if rc != SQLITE_ROW { throw DBError.step(errmsg) }
            let row = Row(stmt: stmt, columns: cols)
            var dict: [String: Any] = [:]
            for (name, i) in cols {
                let c = Int32(i)
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_NULL: dict[name] = NSNull()
                case SQLITE_INTEGER: dict[name] = row.int(name)
                case SQLITE_FLOAT: dict[name] = row.double(name)
                case SQLITE_BLOB: dict[name] = row.data(name) ?? Data()
                default: dict[name] = row.string(name) ?? ""
                }
            }
            out.append(dict)
        }
        return out
    }

    @discardableResult
    func run(_ sql: String, _ params: [SQLValue] = []) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError.step(errmsg) }
        return sqlite3_last_insert_rowid(handle)
    }

    func queryMapped<T>(_ sql: String, _ params: [SQLValue] = [], _ map: (Row) -> T) -> [T] {
        lock.lock(); defer { lock.unlock() }
        guard let stmt = try? prepare(sql, params) else { return [] }
        defer { sqlite3_finalize(stmt) }
        let cols = columnIndexes(stmt)
        var out: [T] = []
        out.reserveCapacity(64)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            if rc != SQLITE_ROW { break }
            out.append(map(Row(stmt: stmt, columns: cols)))
        }
        return out
    }

    func scalar(_ sql: String, _ params: [SQLValue] = []) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
    }
}

extension Database {
    func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS items (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            kind        TEXT NOT NULL,
            text        TEXT,
            data        BLOB,
            paths       TEXT,
            filename    TEXT,
            uti         TEXT,
            preview     TEXT NOT NULL DEFAULT '',
            tags        TEXT NOT NULL DEFAULT '',
            source_app  TEXT,
            source_name TEXT,
            created_at  REAL NOT NULL,
            is_pinned   INTEGER NOT NULL DEFAULT 0,
            is_snippet  INTEGER NOT NULL DEFAULT 0,
            stack_order INTEGER,
            byte_size   INTEGER NOT NULL DEFAULT 0,
            hash        TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_items_hash    ON items(hash);
        CREATE INDEX IF NOT EXISTS idx_items_pinned  ON items(is_pinned);
        CREATE INDEX IF NOT EXISTS idx_items_source  ON items(source_app);

        CREATE TABLE IF NOT EXISTS app_usage (
            bundle_id  TEXT PRIMARY KEY,
            name       TEXT,
            clip_count INTEGER NOT NULL DEFAULT 0,
            last_seen  REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS settings (
            key   TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE TABLE IF NOT EXISTS boards (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT NOT NULL,
            tint       TEXT NOT NULL,
            sort       INTEGER NOT NULL DEFAULT 0,
            is_default INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        """)

        if try scalar("SELECT COUNT(*) FROM boards") == 0 {
            try run("INSERT INTO boards (name, tint, sort, is_default, created_at) VALUES (?,?,?,1,?)",
                    [.text("Clipboard"), .text(Board.palette[5]), .int(0),
                     .double(Date().timeIntervalSince1970)])
        }

        try exec("""
        DROP TRIGGER IF EXISTS items_ai;
        DROP TRIGGER IF EXISTS items_ad;
        DROP TRIGGER IF EXISTS items_au;
        DROP TABLE IF EXISTS items_fts;
        """)

        if !columnExists("items", "board_id") {
            try exec("ALTER TABLE items ADD COLUMN board_id INTEGER NOT NULL DEFAULT 0")
        }
        if !columnExists("items", "source_tint") {
            try exec("ALTER TABLE items ADD COLUMN source_tint TEXT")
        }
        if !columnExists("items", "link_title") {
            try exec("ALTER TABLE items ADD COLUMN link_title TEXT")
        }
        try exec("CREATE INDEX IF NOT EXISTS idx_items_board ON items(board_id)")

        try exec("""
        UPDATE items
           SET board_id = (SELECT id FROM boards WHERE is_default = 1 LIMIT 1)
         WHERE board_id = 0
        """)
    }

    func columnExists(_ table: String, _ column: String) -> Bool {
        let rows = (try? query("PRAGMA table_info(\(table))")) ?? []
        return rows.contains { ($0["name"] as? String) == column }
    }
}
