import Foundation

/// Links the app opens: Top Shelf items, the system's "open this" requests. Only these three shapes exist, with plain
/// numeric ids, so a link can never carry a path, a server address or a password.
///   videoplayer://item/42      a movie or an episode (opens its detail page)
///   videoplayer://series/7     a show (opens its seasons)
///   videoplayer://library      the Home tab
public enum DeepLink: Equatable, Sendable {
    case item(Int64)
    case series(Int64)
    case library

    public static let scheme = "videoplayer"

    public var url: URL {
        switch self {
        case .item(let id): return URL(string: "\(Self.scheme)://item/\(id)")!
        case .series(let id): return URL(string: "\(Self.scheme)://series/\(id)")!
        case .library: return URL(string: "\(Self.scheme)://library")!
        }
    }

    /// nil for anything that is not exactly one of the three shapes.
    public static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == scheme, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        switch (host, parts.count) {
        case ("library", 0): return .library
        case ("item", 1): return Self.id(parts[0]).map(DeepLink.item)
        case ("series", 1): return Self.id(parts[0]).map(DeepLink.series)
        default: return nil
        }
    }

    private static func id(_ text: String) -> Int64? {
        guard !text.isEmpty, text.count <= 18, text.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int64(text), v > 0 else { return nil }
        return v
    }
}
