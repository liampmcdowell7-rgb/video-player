import XCTest
@testable import VideoPlayerCore

final class FileModelTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(FileClassifier.kind(forName: "a.MKV", isDirectory: false), .video)
        XCTAssertEqual(FileClassifier.kind(forName: "a.m2ts", isDirectory: false), .video)
        XCTAssertEqual(FileClassifier.kind(forName: "a.srt", isDirectory: false), .subtitle)
        XCTAssertEqual(FileClassifier.kind(forName: "poster.jpg", isDirectory: false), .image)
        XCTAssertEqual(FileClassifier.kind(forName: "movie.nfo", isDirectory: false), .nfo)
        XCTAssertEqual(FileClassifier.kind(forName: "notes.txt", isDirectory: false), .other)
        XCTAssertEqual(FileClassifier.kind(forName: "Season 1", isDirectory: true), .directory)
        XCTAssertEqual(FileClassifier.kind(forName: ".hidden", isDirectory: false), .other)
    }

    private func item(_ name: String, dir: Bool = false, size: Int64? = nil, date: Double? = nil) -> FileItem {
        FileItem(path: "/x/" + name, name: name, kind: FileClassifier.kind(forName: name, isDirectory: dir),
                 size: size, modified: date.map { Date(timeIntervalSince1970: $0) })
    }

    func testNaturalNameSortWithFoldersFirst() {
        let items = [item("Episode 10.mkv"), item("episode 2.mkv"), item("Zeta", dir: true), item("Alpha", dir: true)]
        let sorted = FileSort(key: .name, ascending: true).apply(to: items).map(\.name)
        XCTAssertEqual(sorted, ["Alpha", "Zeta", "episode 2.mkv", "Episode 10.mkv"])
        let descending = FileSort(key: .name, ascending: false).apply(to: items).map(\.name)
        XCTAssertEqual(descending, ["Zeta", "Alpha", "Episode 10.mkv", "episode 2.mkv"])
    }

    func testSortBySizeAndDate() {
        let items = [item("b.mkv", size: 300, date: 10), item("a.mkv", size: 100, date: 30), item("c.mkv", size: 200, date: 20)]
        XCTAssertEqual(FileSort(key: .size, ascending: true).apply(to: items).map(\.name), ["a.mkv", "c.mkv", "b.mkv"])
        XCTAssertEqual(FileSort(key: .dateModified, ascending: false).apply(to: items).map(\.name), ["a.mkv", "c.mkv", "b.mkv"])
    }

    func testSearchMatchesAllWordsIgnoringCaseAndDiacritics() {
        let items = [item("Amélise Lanterne (2001).mkv"), item("Harbor Lights S01E01.mkv"), item("notes.txt")]
        XCTAssertEqual(FileSearch.filter(items, query: "amelise 2001").map(\.name), ["Amélise Lanterne (2001).mkv"])
        XCTAssertEqual(FileSearch.filter(items, query: "harbor s01e01").count, 1)
        XCTAssertEqual(FileSearch.filter(items, query: "  ").count, 3)
        XCTAssertEqual(FileSearch.filter(items, query: "zzz").count, 0)
    }

    func testPathHelpers() {
        let file = FileItem(path: "/TV/Harbor Lights/Season 1/e01.mkv", name: "e01.mkv", kind: .video)
        XCTAssertEqual(file.parentPath, "/TV/Harbor Lights/Season 1")
        XCTAssertEqual(file.ancestorFolderNames, ["Season 1", "Harbor Lights", "TV"])
        let root = FileItem(path: "/a.mkv", name: "a.mkv", kind: .video)
        XCTAssertEqual(root.parentPath, "/")
        XCTAssertEqual(root.ancestorFolderNames, [])
    }

    func testFileItemFromEntry() {
        let entry = SourceEntry(path: "/Movies/x.mkv", name: "x.mkv", isDirectory: false, size: 5, modified: nil, contentType: nil, etag: "e")
        let item = FileItem(entry: entry)
        XCTAssertTrue(item.isVideo)
        XCTAssertEqual(item.size, 5)
        XCTAssertEqual(item.etag, "e")
    }
}
