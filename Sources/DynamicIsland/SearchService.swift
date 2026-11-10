import AppKit

struct SearchResult: Identifiable {
    enum Kind { case app, file, web }
    let id: String
    let title: String
    let subtitle: String
    let icon: NSImage
    let kind: Kind
    let url: URL
}

/// Spotlight-style search: apps (instant), files in your home folder (Spotlight index),
/// plus Google / YouTube web search.
final class SearchService: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    @Published private(set) var results: [SearchResult] = []
    @Published var selection = 0

    private var apps: [(name: String, url: URL)] = []
    private var fileResults: [SearchResult] = []
    private var mdQuery: NSMetadataQuery?
    private var mdObserver: NSObjectProtocol?
    private var debounce: DispatchWorkItem?

    init() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = SearchService.scanApps()
            DispatchQueue.main.async { self?.apps = found }
        }
    }

    // MARK: Public

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func activateSelection() {
        guard results.indices.contains(selection) else { return }
        NSWorkspace.shared.open(results[selection].url)
    }

    // MARK: Query handling

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func queryChanged() {
        let q = trimmed
        selection = 0
        stopFileSearch()
        fileResults = []
        debounce?.cancel()
        guard !q.isEmpty else { results = []; return }
        rebuild(for: q)
        let work = DispatchWorkItem { [weak self] in self?.startFileSearch(q) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func rebuild(for q: String) {
        let lower = q.lowercased()
        let scored: [(Int, SearchResult)] = apps.compactMap { app in
            let name = app.name.lowercased()
            let score: Int
            if name.hasPrefix(lower) { score = 0 }
            else if name.split(separator: " ").contains(where: { $0.hasPrefix(lower) }) { score = 1 }
            else if name.contains(lower) { score = 2 }
            else if Self.initials(name).hasPrefix(lower) { score = 3 }
            else { return nil }
            let result = SearchResult(id: app.url.path, title: app.name, subtitle: "Application",
                                      icon: NSWorkspace.shared.icon(forFile: app.url.path),
                                      kind: .app, url: app.url)
            return (score, result)
        }
        let appHits = scored
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.title.count < $1.1.title.count }
            .prefix(5)
            .map { $0.1 }
        results = Array(appHits) + fileResults + webResults(for: q)
        if selection >= results.count { selection = 0 }
    }

    private func webResults(for q: String) -> [SearchResult] {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let enc = q.addingPercentEncoding(withAllowedCharacters: allowed) ?? q
        var out: [SearchResult] = []

        // Looks like a web address? Offer to open it directly.
        if !q.contains(" "), q.contains("."), let url = URL(string: q.hasPrefix("http") ? q : "https://\(q)"), url.host != nil {
            out.append(SearchResult(id: "web-open", title: "Open \(url.host ?? q)", subtitle: "Website",
                                    icon: Self.symbol("safari"), kind: .web, url: url))
        }
        if let g = URL(string: "https://www.google.com/search?q=\(enc)") {
            out.append(SearchResult(id: "web-google", title: "Search Google for “\(q)”", subtitle: "Web",
                                    icon: Self.symbol("globe"), kind: .web, url: g))
        }
        if let y = URL(string: "https://www.youtube.com/results?search_query=\(enc)") {
            out.append(SearchResult(id: "web-youtube", title: "Search YouTube for “\(q)”", subtitle: "YouTube",
                                    icon: Self.symbol("play.rectangle.fill"), kind: .web, url: y))
        }
        return out
    }

    // MARK: File search via Spotlight index

    private func startFileSearch(_ q: String) {
        guard q == trimmed else { return }
        let mq = NSMetadataQuery()
        mq.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemDisplayNameKey, q)
        mq.searchScopes = [NSMetadataQueryUserHomeScope]
        mq.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]

        mdObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                                            object: mq, queue: .main) { [weak self, weak mq] _ in
            guard let self, let mq else { return }
            mq.disableUpdates()
            var out: [SearchResult] = []
            let limit = min(mq.resultCount, 60)
            for i in 0..<limit {
                guard let item = mq.result(at: i) as? NSMetadataItem,
                      let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                if path.hasSuffix(".app") || path.contains("/Library/") || path.contains("/.") { continue }
                let url = URL(fileURLWithPath: path)
                let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                out.append(SearchResult(id: path, title: url.lastPathComponent, subtitle: folder,
                                        icon: NSWorkspace.shared.icon(forFile: path), kind: .file, url: url))
                if out.count >= 6 { break }
            }
            self.stopFileSearch()
            guard q == self.trimmed else { return }
            self.fileResults = out
            self.rebuild(for: q)
        }
        mdQuery = mq
        mq.start()
    }

    private func stopFileSearch() {
        mdQuery?.stop()
        mdQuery = nil
        if let mdObserver { NotificationCenter.default.removeObserver(mdObserver) }
        mdObserver = nil
    }

    // MARK: Helpers

    private static func scanApps() -> [(name: String, url: URL)] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                    "/System/Applications/Utilities", NSHomeDirectory() + "/Applications",
                    "/System/Library/CoreServices/Applications"]
        var seen = Set<String>()
        var out: [(name: String, url: URL)] = []
        func add(_ name: String, _ url: URL) {
            if seen.insert(name.lowercased()).inserted { out.append((name: name, url: url)) }
        }
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                let full = URL(fileURLWithPath: dir).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    add(String(item.dropLast(4)), full)
                } else if let sub = try? fm.contentsOfDirectory(atPath: full.path) {
                    // one level deep, e.g. /Applications/Microsoft Office/…
                    for s in sub where s.hasSuffix(".app") {
                        add(String(s.dropLast(4)), full.appendingPathComponent(s))
                    }
                }
            }
        }
        add("Finder", URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        return out
    }

    private static func initials(_ s: String) -> String {
        String(s.split(separator: " ").compactMap { $0.first })
    }

    private static func symbol(_ name: String) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        return img
    }
}
