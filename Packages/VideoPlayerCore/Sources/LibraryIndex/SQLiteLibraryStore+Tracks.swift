import Foundation

/// What the file's own header says about its tracks (#21 C, OPEN_QUESTIONS R192, PROVISIONAL): the frame rate, every audio
/// track and every embedded subtitle track. The scan does not read this (it would open every file); it is read when a
/// detail page opens and kept here, tied to the file's size, so it is read once per file version.
public struct FileTrackDetails: Equatable, Sendable, Codable {
    public struct Audio: Equatable, Sendable, Codable {
        /// The codec's short name ("truehd", "eac3", "aac"), or the container's own CodecID when it is not a known one.
        public var codec: String
        public var channels: Int?
        /// BCP 47 or ISO 639-2 code, as in the file.
        public var language: String?
        public var name: String?
        public var isDefault: Bool
        public var isCommentary: Bool

        public init(codec: String, channels: Int?, language: String?, name: String?, isDefault: Bool, isCommentary: Bool = false) {
            self.codec = codec
            self.channels = channels
            self.language = language
            self.name = name
            self.isDefault = isDefault
            self.isCommentary = isCommentary
        }
    }

    public struct Subtitle: Equatable, Sendable, Codable {
        public var codec: String
        public var language: String?
        public var name: String?
        public var isForced: Bool
        public var isHearingImpaired: Bool

        public init(codec: String, language: String?, name: String?, isForced: Bool, isHearingImpaired: Bool) {
            self.codec = codec
            self.language = language
            self.name = name
            self.isForced = isForced
            self.isHearingImpaired = isHearingImpaired
        }
    }

    public var frameRate: Double?
    public var audio: [Audio]
    public var subtitles: [Subtitle]

    public init(frameRate: Double?, audio: [Audio], subtitles: [Subtitle]) {
        self.frameRate = frameRate
        self.audio = audio
        self.subtitles = subtitles
    }
}

extension SQLiteLibraryStore {
    /// The cached track details of a file, or nil when they were never read or the file changed size since.
    public func trackDetails(fileID: Int64) throws -> FileTrackDetails? {
        let row = try db.first("""
            SELECT t.data FROM file_tracks t JOIN files f ON f.id = t.file_id
            WHERE t.file_id = ? AND f.removed_at IS NULL AND (t.size IS f.size)
            """, [.int(fileID)]) { $0.text(0) }
        guard let json = row, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FileTrackDetails.self, from: data)
    }

    /// Keeps the details read from the file, with the file's current size (a replaced file is read again).
    public func setTrackDetails(fileID: Int64, _ details: FileTrackDetails) throws {
        let data = try JSONEncoder().encode(details)
        let json = String(decoding: data, as: UTF8.self)
        try db.transaction {
            guard let size = try db.first("SELECT size FROM files WHERE id = ?", [.int(fileID)], { $0.optInt64(0) }) else {
                throw LibraryIndexError.notFound("file \(fileID)")
            }
            try db.run("INSERT OR REPLACE INTO file_tracks (file_id, size, data, read_at) VALUES (?, ?, ?, ?)",
                       [.int(fileID), SQLValue(size), .text(json), SQLValue(Date())])
        }
    }

    /// Drops the details of files that are gone (after a purge or a removed source).
    func dropOrphanTrackDetails() throws {
        try db.run("DELETE FROM file_tracks WHERE file_id NOT IN (SELECT id FROM files)")
    }
}
