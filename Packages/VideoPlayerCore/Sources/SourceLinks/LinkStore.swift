import Foundation
import VideoPlayerCore

public struct SavedLink: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// What the user sees (and the file name in the list). Unique inside a store, ignoring case.
    public var title: String
    /// The address exactly as pasted (trimmed). Conversion happens when it is played, not when it is saved.
    public var urlString: String

    public init(id: UUID = UUID(), title: String, urlString: String) {
        self.id = id
        self.title = title
        self.urlString = urlString
    }

    public var url: URL? { URL(string: urlString) }
}

/// The user's list of pasted links. A plain value: the app saves it as JSON (`encoded()`), for example in
/// the app's own storage. Links can hold secret tokens in the query, so keep it out of logs and backups you share.
public struct LinkStore: Codable, Equatable, Sendable {
    public private(set) var links: [SavedLink]

    public init(links: [SavedLink] = []) { self.links = links }

    // MARK: Validate

    /// Checks pasted text and returns the address to save. Does not touch the network.
    public static func validate(_ text: String) -> Result<URL, LinkError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), url.host?.isEmpty == false else { return .failure(.invalidLink) }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return .failure(.notWebLink) }
        if url.user != nil || url.password != nil { return .failure(.credentialsInLink) }
        return .success(url)
    }

    /// A name for a link nobody named: the file name in the address, or the host.
    public static func defaultTitle(for url: URL) -> String {
        let last = url.path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
        if let last, let decoded = last.removingPercentEncoding, !decoded.isEmpty { return decoded }
        return url.host ?? "Link"
    }

    // MARK: Change the list

    /// Adds a link. A missing title is made from the address; a taken title gets " (2)", " (3)"...
    /// Throws for text that is not a web address and for an address that is already in the list.
    @discardableResult
    public mutating func add(_ text: String, title: String? = nil) throws -> SavedLink {
        let url = try Self.validate(text).get()
        if let existing = links.first(where: { Self.sameAddress($0.urlString, url.absoluteString) }) {
            throw LinkError.duplicate(existingTitle: existing.title)
        }
        let wanted = Self.clean(title) ?? Self.defaultTitle(for: url)
        let link = SavedLink(title: uniqueTitle(wanted, excluding: nil), urlString: url.absoluteString)
        links.append(link)
        return link
    }

    public mutating func remove(id: UUID) {
        links.removeAll { $0.id == id }
    }

    /// Gives a link a new name. A name used by another link gets a number added.
    public mutating func rename(id: UUID, to newTitle: String) throws {
        guard let index = links.firstIndex(where: { $0.id == id }) else { throw LinkError.notFound(newTitle) }
        guard let cleaned = Self.clean(newTitle) else { return }
        links[index].title = uniqueTitle(cleaned, excluding: id)
    }

    public func link(id: UUID) -> SavedLink? { links.first { $0.id == id } }

    public func link(titled title: String) -> SavedLink? {
        links.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    // MARK: Save and load

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LinkStore {
        try JSONDecoder().decode(LinkStore.self, from: data)
    }

    // MARK: Helpers

    private static func clean(_ title: String?) -> String? {
        guard let title else { return nil }
        let replaced = title.replacingOccurrences(of: "/", with: "\u{2215}").trimmingCharacters(in: .whitespacesAndNewlines)
        return replaced.isEmpty ? nil : replaced
    }

    private func uniqueTitle(_ wanted: String, excluding id: UUID?) -> String {
        let taken = Set(links.filter { $0.id != id }.map { $0.title.lowercased() })
        if !taken.contains(wanted.lowercased()) { return wanted }
        let ext = (wanted as NSString).pathExtension
        let stem = ext.isEmpty ? wanted : String(wanted.dropLast(ext.count + 1))
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            counter += 1
        }
    }

    /// Same address, ignoring case in the scheme and host and a trailing slash.
    private static func sameAddress(_ a: String, _ b: String) -> Bool {
        func key(_ text: String) -> String {
            guard var c = URLComponents(string: text) else { return text }
            c.scheme = c.scheme?.lowercased()
            c.host = c.host?.lowercased()
            if c.path.hasSuffix("/"), c.path.count > 1 { c.path.removeLast() }
            return c.string ?? text
        }
        return key(a) == key(b)
    }
}
