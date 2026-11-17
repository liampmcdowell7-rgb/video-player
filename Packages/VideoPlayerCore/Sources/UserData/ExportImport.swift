import Foundation

public enum UDExportError: Error, Equatable, Sendable {
    case notAnExport
    case unsupportedVersion(Int)
    case damaged(String)
}

/// A backup the user can keep (shown in Settings, mainly for people who are not signed in to iCloud). Versioned,
/// stable (the same data always gives the same bytes), and merged on import with the normal stamp rules, so
/// importing an old backup never overwrites newer data. It contains no secrets: passwords are not in any record.
public enum UDExport {
    public static let format = "video-player-userdata"
    public static let version = 1

    private struct Body: Codable {
        var format: String
        var version: Int
        var exportedAt: Double
        var records: [UDRecord]
    }

    public static func export(_ ledger: UserDataLedger, at date: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(Body(format: format, version: version, exportedAt: date.timeIntervalSince1970, records: ledger.allRecords()))
    }

    /// Merges the backup into the ledger. Returns how many records changed.
    @discardableResult
    public static func `import`(_ data: Data, into ledger: UserDataLedger) throws -> Int {
        let body: Body
        do { body = try JSONDecoder().decode(Body.self, from: data) } catch {
            // Distinguish "not our file" from "our file, damaged".
            if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any], any["format"] as? String == format {
                throw UDExportError.damaged("\(error)")
            }
            throw UDExportError.notAnExport
        }
        guard body.format == format else { throw UDExportError.notAnExport }
        guard body.version == version else { throw UDExportError.unsupportedVersion(body.version) }
        return body.records.reduce(0) { $0 + (ledger.apply($1) ? 1 : 0) }
    }
}
