import Foundation

/// The database layout. `PRAGMA user_version` holds the schema number; each step in `migrations` upgrades by one.
/// A database written by a newer app is refused (`LibraryIndexError.newerSchema`), never modified.
enum LibrarySchema {
    static let currentVersion = 5

    static let pragmas = """
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    PRAGMA temp_store = MEMORY;
    PRAGMA cache_size = -16000;
    PRAGMA foreign_keys = OFF;
    """

    /// Index n upgrades from version n to n + 1.
    static let migrations: [[String]] = [
        // 0 -> 1
        [
            """
            CREATE TABLE sources (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                added_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE series (
                id INTEGER PRIMARY KEY,
                key TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                tmdb_id INTEGER
            )
            """,
            // One row per film or episode. Aggregates over its live files and the watch state live here too,
            // so every filter, sort and home-screen row reads a single table.
            """
            CREATE TABLE items (
                id INTEGER PRIMARY KEY,
                key TEXT NOT NULL UNIQUE,
                kind INTEGER NOT NULL,
                title TEXT NOT NULL,
                sort_title TEXT NOT NULL,
                letter TEXT NOT NULL,
                search TEXT NOT NULL,
                year INTEGER NOT NULL DEFAULT 0,
                rating REAL NOT NULL DEFAULT 0,
                series_id INTEGER,
                series_title TEXT,
                season INTEGER,
                episode INTEGER,
                episode_end INTEGER,
                tmdb_id INTEGER,
                added_at REAL NOT NULL,
                version_count INTEGER NOT NULL DEFAULT 0,
                pref_file_id INTEGER,
                effective_file_id INTEGER,
                max_res INTEGER NOT NULL DEFAULT -1,
                hdr_mask INTEGER NOT NULL DEFAULT 0,
                dv_mask INTEGER NOT NULL DEFAULT 0,
                max_channels INTEGER NOT NULL DEFAULT 0,
                atmos INTEGER NOT NULL DEFAULT 0,
                container_mask INTEGER NOT NULL DEFAULT 0,
                runtime REAL NOT NULL DEFAULT 0,
                position REAL NOT NULL DEFAULT 0,
                wduration REAL,
                watched INTEGER NOT NULL DEFAULT 0,
                play_count INTEGER NOT NULL DEFAULT 0,
                last_played REAL NOT NULL DEFAULT 0,
                favorite INTEGER NOT NULL DEFAULT 0,
                hidden INTEGER NOT NULL DEFAULT 0
            )
            """,
            "CREATE TABLE item_genres (item_id INTEGER NOT NULL, genre TEXT NOT NULL COLLATE NOCASE, PRIMARY KEY (item_id, genre)) WITHOUT ROWID",
            "CREATE INDEX idx_genres ON item_genres (genre, item_id)",
            """
            CREATE TABLE files (
                id INTEGER PRIMARY KEY,
                source_id TEXT NOT NULL,
                path TEXT NOT NULL,
                name TEXT NOT NULL,
                name_key TEXT NOT NULL,
                parent TEXT NOT NULL,
                kind INTEGER NOT NULL,
                size INTEGER,
                modified REAL,
                etag TEXT,
                token TEXT,
                item_id INTEGER,
                first_seen REAL NOT NULL,
                removed_at REAL,
                version_label TEXT,
                has_tech INTEGER NOT NULL DEFAULT 0,
                duration REAL,
                container INTEGER,
                width INTEGER,
                height INTEGER,
                res INTEGER NOT NULL DEFAULT -1,
                hdr_mask INTEGER NOT NULL DEFAULT 0,
                dv_profile INTEGER,
                vcodec TEXT,
                acodec TEXT,
                channels INTEGER NOT NULL DEFAULT 0,
                atmos INTEGER NOT NULL DEFAULT 0,
                bitrate INTEGER,
                UNIQUE (source_id, path)
            )
            """,
            "CREATE INDEX idx_files_parent ON files (source_id, parent, name_key)",
            "CREATE INDEX idx_files_item ON files (item_id)",
            "CREATE INDEX idx_files_removed ON files (removed_at) WHERE removed_at IS NOT NULL",
            """
            CREATE TABLE folders (
                source_id TEXT NOT NULL,
                path TEXT NOT NULL,
                name TEXT NOT NULL,
                name_key TEXT NOT NULL,
                parent TEXT NOT NULL,
                obs_etag TEXT, obs_modified REAL, obs_size INTEGER, obs_token TEXT,
                scan_etag TEXT, scan_modified REAL, scan_size INTEGER, scan_token TEXT,
                scanned INTEGER NOT NULL DEFAULT 0,
                empty_strikes INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                last_scanned REAL,
                removed_at REAL,
                PRIMARY KEY (source_id, path)
            ) WITHOUT ROWID
            """,
            "CREATE INDEX idx_folders_parent ON folders (source_id, parent, name_key)",
            """
            CREATE TABLE scans (
                id INTEGER PRIMARY KEY,
                source_id TEXT NOT NULL,
                roots TEXT NOT NULL,
                recursive INTEGER NOT NULL,
                trust INTEGER NOT NULL,
                status TEXT NOT NULL,
                started_at REAL NOT NULL,
                finished_at REAL,
                folders_done INTEGER NOT NULL DEFAULT 0
            )
            """,
            "CREATE INDEX idx_scans_source ON scans (source_id, status)",
            """
            CREATE TABLE scan_queue (
                id INTEGER PRIMARY KEY,
                scan_id INTEGER NOT NULL,
                source_id TEXT NOT NULL,
                path TEXT NOT NULL,
                done INTEGER NOT NULL DEFAULT 0,
                UNIQUE (scan_id, path)
            )
            """,
            "CREATE INDEX idx_queue_next ON scan_queue (scan_id, done, id)",
            """
            CREATE TABLE views (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                scope_kind INTEGER NOT NULL,
                scope_source TEXT NOT NULL DEFAULT '',
                scope_path TEXT NOT NULL DEFAULT '',
                query TEXT NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                position INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            )
            """,
            "CREATE INDEX idx_views_scope ON views (scope_kind, scope_source, scope_path, position)",

            // Grid sorts. Every query adds "version_count > 0", which these partial indexes match.
            "CREATE INDEX idx_items_title ON items (sort_title, id) WHERE version_count > 0",
            "CREATE INDEX idx_items_letter ON items (letter) WHERE version_count > 0",
            "CREATE INDEX idx_items_year ON items (year, id) WHERE version_count > 0",
            "CREATE INDEX idx_items_rating ON items (rating, id) WHERE version_count > 0",
            "CREATE INDEX idx_items_added ON items (added_at, id) WHERE version_count > 0",
            "CREATE INDEX idx_items_played ON items (last_played, id) WHERE version_count > 0",
            "CREATE INDEX idx_items_runtime ON items (runtime, id) WHERE version_count > 0",
            "CREATE INDEX idx_items_series ON items (series_id, season, episode) WHERE series_id IS NOT NULL",
            // Home rows.
            "CREATE INDEX idx_items_continue ON items (last_played) WHERE watched = 0 AND position > 0",
            "CREATE INDEX idx_items_watched ON items (series_id, last_played) WHERE watched = 1 AND kind = 1",
        ],
        // 1 -> 2: saved views get a uid that is the same on every device (the key of their cloud record).
        [
            "ALTER TABLE views ADD COLUMN uid TEXT",
            "UPDATE views SET uid = lower(hex(randomblob(16))) WHERE uid IS NULL",
            "CREATE UNIQUE INDEX idx_views_uid ON views (uid)",
        ],
        // 2 -> 3: per-file sorting (docs/SORTING.md). Which signal sorted each file, the Needs Review flag, and the rule
        // revision (0 here, so every existing file is sorted again by the new rules on the next scan).
        [
            "ALTER TABLE items ADD COLUMN review INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE files ADD COLUMN sort_signal TEXT",
            "ALTER TABLE files ADD COLUMN sort_note TEXT",
            "ALTER TABLE files ADD COLUMN sort_rev INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE files ADD COLUMN sort_inputs TEXT NOT NULL DEFAULT ''",
            "ALTER TABLE files ADD COLUMN review INTEGER NOT NULL DEFAULT 0",
            "CREATE INDEX idx_items_review ON items (added_at, id) WHERE review = 1 AND version_count > 0",
        ],
        // 3 -> 4: the year in each episode file's show name (addendum #18 D), so shows with one name and different years
        // stay apart. Empty here; every file is sorted again once (MediaSorter.revision 2), which fills it.
        [
            "ALTER TABLE files ADD COLUMN series_year INTEGER",
        ],
        // 4 -> 5: a file with no year whose show name is shared by two shows with different years waits in Needs Review
        // (addendum #19 C). This holds where it came from (plain item key, signal, note), so it goes back by itself when
        // only one year is left, and a rescan leaves it alone. NULL for every other file.
        [
            "ALTER TABLE files ADD COLUMN shared_name TEXT",
            "CREATE INDEX idx_files_shared_name ON files (shared_name) WHERE shared_name IS NOT NULL",
        ],
    ]
}

extension SQLiteDatabase {
    /// Opens (creating if needed) and upgrades to the current schema.
    func prepareLibrarySchema() throws {
        let found = try scalarInt("PRAGMA user_version")
        if found > LibrarySchema.currentVersion {
            throw LibraryIndexError.newerSchema(found: found, supported: LibrarySchema.currentVersion)
        }
        try exec(LibrarySchema.pragmas)
        var version = found
        while version < LibrarySchema.currentVersion {
            let statements = LibrarySchema.migrations[version]
            try transaction {
                for sql in statements { try exec(sql) }
                try exec("PRAGMA user_version = \(version + 1)")
            }
            version += 1
        }
    }
}
