import Foundation
import VideoPlayerCore

// Discovery first (docs/SOURCE_SETUP_DESIGN.md, OPEN_QUESTIONS R326 and R328, both PROVISIONAL): which forms start with a
// Search Your Network row, what the search page says while it looks, and how a found server fills a form that may already
// have typed values. Plain data, so the Linux tests prove it; DiscoveryView and SourceFormView only apply it.
public enum SourceDiscoveryText {
    /// True when the network search can find servers of this type, so its form starts with a Search Your Network row.
    /// Only the types the search really looks for (`BonjourMapping.serviceTypes`): UPnP/DLNA keeps `canDiscover` in the
    /// catalog, but the search does not find it (its devices answer a different protocol), so its form has no such row.
    public static func searches(_ kind: SourceKind) -> Bool {
        BonjourMapping.serviceTypes.contains { $0.kind == kind }
    }

    /// The found servers the page lists: all of them on Add a Source's page, only the form's type on a form's page.
    public static func shown(_ found: [DiscoveredSource], kind: SourceKind?) -> [DiscoveredSource] {
        guard let kind else { return found }
        return found.filter { $0.kind == kind }
    }

    /// The section footer of the search page (R328: never a row with a spinner). While nothing is found it says what is
    /// looked for; once something is listed it says what to do when a server is missing.
    public static func footer(kind: SourceKind?, foundAny: Bool) -> String {
        let missing: String = "If yours is not listed, go back and type its address."
        if foundAny { return missing }
        guard let kind else {
            let titles: [String] = BonjourMapping.serviceTypes.map { SourceCatalog.info(for: $0.kind).title }
            var unique: [String] = []
            for title in titles where !unique.contains(title) { unique.append(title) }
            return "Looking for " + SourceFormText.joined(unique) + " servers on your network. " + missing
                + " UPnP/DLNA servers are not found this way: choose UPnP/DLNA and type the address of its device description."
        }
        return "Looking for " + SourceCatalog.info(for: kind).title + " servers on your network. " + missing
    }

    /// The form after a found server was chosen on its Search Your Network page (R326): the found values replace what the
    /// search knows (server, address, port); a Name already typed stays (it is the person's label), and so does anything
    /// else typed that the search does not know (user name, password, shared folder).
    public static func merged(_ draft: SourceDraft, with found: DiscoveredSource) -> SourceDraft {
        var next: SourceDraft = SourceDraft(discovered: found)
        guard next.kind == draft.kind else { return next }
        let typedName: Bool = !draft[.name].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if typedName { next[.name] = draft[.name] }
        for spec in SourceCatalog.info(for: draft.kind).fields where next[spec.kind].isEmpty && !draft[spec.kind].isEmpty {
            next[spec.kind] = draft[spec.kind]
        }
        return next
    }
}
