import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public enum LibraryIndexError: Error, Equatable, Sendable {
    case sqlite(code: Int32, message: String)
    /// The database file was written by a newer version of the app.
    case newerSchema(found: Int, supported: Int)
    case notFound(String)
    case invalid(String)
}

/// Binds to a statement parameter.
enum SQLValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)

    init(_ v: Int64?) { self = v.map(SQLValue.int) ?? .null }
    init(_ v: Int?) { self = v.map { SQLValue.int(Int64($0)) } ?? .null }
    init(_ v: Double?) { self = v.map(SQLValue.double) ?? .null }
    init(_ v: String?) { self = v.map(SQLValue.text) ?? .null }
    init(_ v: Date?) { self = v.map { SQLValue.double($0.timeIntervalSince1970) } ?? .null }
    init(_ v: Bool) { self = .int(v ? 1 : 0) }
}

private let sqliteTransient = unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)

/// A prepared statement. Not thread safe; owned by one `SQLiteDatabase`, which is owned by one actor.
final class SQLiteStatement {
    fileprivate let handle: OpaquePointer

    fileprivate init(handle: OpaquePointer) { self.handle = handle }
    deinit { sqlite3_finalize(handle) }

    func reset() {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    func bind(_ values: [SQLValue]) {
        for (offset, value) in values.enumerated() {
            let i = Int32(offset + 1)
            switch value {
            case .null: sqlite3_bind_null(handle, i)
            case .int(let v): sqlite3_bind_int64(handle, i, v)
            case .double(let v): sqlite3_bind_double(handle, i, v)
            case .text(let v): sqlite3_bind_text(handle, i, v, -1, sqliteTransient)
            }
        }
    }

    /// Returns true when a row is available, false when done.
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            let db = sqlite3_db_handle(handle)
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "step failed"
            throw LibraryIndexError.sqlite(code: rc, message: message)
        }
    }

    func isNull(_ c: Int32) -> Bool { sqlite3_column_type(handle, c) == SQLITE_NULL }
    func int64(_ c: Int32) -> Int64 { sqlite3_column_int64(handle, c) }
    func int(_ c: Int32) -> Int { Int(sqlite3_column_int64(handle, c)) }
    func double(_ c: Int32) -> Double { sqlite3_column_double(handle, c) }
    func bool(_ c: Int32) -> Bool { sqlite3_column_int64(handle, c) != 0 }
    func text(_ c: Int32) -> String {
        guard let p = sqlite3_column_text(handle, c) else { return "" }
        return String(cString: p)
    }
    func optText(_ c: Int32) -> String? { isNull(c) ? nil : text(c) }
    func optInt64(_ c: Int32) -> Int64? { isNull(c) ? nil : int64(c) }
    func optInt(_ c: Int32) -> Int? { isNull(c) ? nil : int(c) }
    func optDouble(_ c: Int32) -> Double? { isNull(c) ? nil : double(c) }
    func optDate(_ c: Int32) -> Date? { isNull(c) ? nil : Date(timeIntervalSince1970: double(c)) }
}

/// A single SQLite connection. Confined to the actor that owns it.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private var cache: [String: SQLiteStatement] = [:]
    private(set) var transactionDepth = 0

    init(path: String) throws {
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &h, flags, nil)
        guard rc == SQLITE_OK, let opened = h else {
            let message = h.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open \(path)"
            if let h { sqlite3_close(h) }
            throw LibraryIndexError.sqlite(code: rc, message: message)
        }
        handle = opened
        sqlite3_busy_timeout(opened, 5000)
    }

    deinit {
        cache.removeAll()
        if let handle { sqlite3_close_v2(handle) }
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    var changes: Int { Int(sqlite3_changes(handle)) }

    private func error(_ rc: Int32) -> LibraryIndexError {
        .sqlite(code: rc, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed")
    }

    func exec(_ sql: String) throws {
        let rc = sqlite3_exec(handle, sql, nil, nil, nil)
        if rc != SQLITE_OK { throw error(rc) }
    }

    private func statement(_ sql: String, cached: Bool) throws -> SQLiteStatement {
        if cached, let s = cache[sql] { return s }
        var raw: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &raw, nil)
        guard rc == SQLITE_OK, let raw else { throw error(rc) }
        let s = SQLiteStatement(handle: raw)
        if cached {
            if cache.count > 400 { cache.removeAll() }
            cache[sql] = s
        }
        return s
    }

    /// Runs a statement that returns no rows.
    @discardableResult
    func run(_ sql: String, _ args: [SQLValue] = [], cached: Bool = true) throws -> Int {
        let s = try statement(sql, cached: cached)
        s.reset()
        defer { s.reset() }
        s.bind(args)
        while try s.step() {}
        return changes
    }

    /// Runs a query and maps every row.
    func rows<T>(_ sql: String, _ args: [SQLValue] = [], cached: Bool = true, _ map: (SQLiteStatement) throws -> T) throws -> [T] {
        let s = try statement(sql, cached: cached)
        s.reset()
        defer { s.reset() }
        s.bind(args)
        var out: [T] = []
        while try s.step() { out.append(try map(s)) }
        return out
    }

    func first<T>(_ sql: String, _ args: [SQLValue] = [], cached: Bool = true, _ map: (SQLiteStatement) throws -> T) throws -> T? {
        let s = try statement(sql, cached: cached)
        s.reset()
        defer { s.reset() }
        s.bind(args)
        if try s.step() { return try map(s) }
        return nil
    }

    func scalarInt(_ sql: String, _ args: [SQLValue] = []) throws -> Int {
        try first(sql, args) { $0.int(0) } ?? 0
    }

    /// Copies this whole database into `other`, replacing its content, with SQLite's online backup API
    /// (https://sqlite.org/backup.html): all pages in one step, all or nothing. Page numbers are kept, so a page that did
    /// not change has the same bytes in every copy (the iCloud backup's incremental upload relies on it).
    func copy(into other: SQLiteDatabase) throws {
        guard let backup = sqlite3_backup_init(other.handle, "main", handle, "main") else {
            throw other.error(sqlite3_errcode(other.handle))
        }
        let rc = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard rc == SQLITE_DONE else { throw LibraryIndexError.sqlite(code: rc, message: "backup step failed") }
        guard finish == SQLITE_OK else { throw other.error(finish) }
    }

    /// Nested calls join the outer transaction.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        if transactionDepth > 0 { return try body() }
        try exec("BEGIN IMMEDIATE")
        transactionDepth = 1
        do {
            let result = try body()
            transactionDepth = 0
            try exec("COMMIT")
            return result
        } catch {
            transactionDepth = 0
            try? exec("ROLLBACK")
            throw error
        }
    }
}

enum SQLiteInfo {
    static var version: String { String(cString: sqlite3_libversion()) }
}
