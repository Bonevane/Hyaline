// Sources for configurable widgets: script output, GitHub contributions and RSS feeds.

import AppKit
import EventKit
import CoreLocation
import IOKit

/// Runs a shell command on a schedule and keeps its last output.
final class ScriptSource: ObservableObject {
    @Published var output = ""
    @Published var ranAt: Date?
    var command: String { didSet { run() } }
    private var timer: Timer?
    init(command: String) {
        self.command = command
        run()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.run() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    deinit { timer?.invalidate() }
    func run() {
        guard !command.isEmpty else { output = ""; return }
        let cmd = command
        DispatchQueue.global(qos: .utility).async {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", cmd]
            p.standardOutput = pipe; p.standardError = pipe
            try? p.run(); p.waitUntilExit()
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async { self.output = text.trimmingCharacters(in: .whitespacesAndNewlines); self.ranAt = Date() }
        }
    }
}

/// A user's public GitHub contribution levels (0–4), oldest first, read from the
/// same page github.com shows on profiles. No token needed.
final class GitHubSource: ObservableObject {
    @Published var levels: [Int] = []
    @Published var total: String?
    var user: String { didSet { fetch() } }
    init(user: String) { self.user = user; fetch() }
    func fetch() {
        guard !user.isEmpty, let url = URL(string: "https://github.com/users/\(user)/contributions") else { levels = []; return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let html = String(data: data, encoding: .utf8) else { return }
            let re = try! NSRegularExpression(pattern: #"data-date="(\d{4}-\d{2}-\d{2})"[^>]*data-level="(\d)""#)
            let ns = html as NSString
            let cells = re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
                (ns.substring(with: $0.range(at: 1)), Int(ns.substring(with: $0.range(at: 2))) ?? 0)
            }.sorted { $0.0 < $1.0 }
            let totalRe = try! NSRegularExpression(pattern: #"([\d,]+)\s+contributions?\s+in the last year"#)
            let total = totalRe.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
            DispatchQueue.main.async { self.levels = cells.map(\.1); self.total = total }
        }.resume()
    }
}

/// The newest items of an RSS or Atom feed.
final class FeedSource: NSObject, ObservableObject, XMLParserDelegate {
    struct Item: Identifiable { let id = UUID(); let title: String; let date: Date? }
    @Published var items: [Item] = []
    @Published var feedTitle = ""
    var url: String { didSet { fetch() } }
    private var parsed: [Item] = [], current = "", text = "", itemTitle = "", itemDate: Date?, inItem = false, channelTitle = ""
    init(url: String) {
        self.url = url
        super.init()
        fetch()
        let t = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.fetch() }
        RunLoop.main.add(t, forMode: .common)
    }
    func fetch() {
        guard let u = URL(string: url), !url.isEmpty else { items = []; return }
        URLSession.shared.dataTask(with: u) { data, _, _ in
            guard let data else { return }
            let parser = XMLParser(data: data)
            self.parsed = []; self.channelTitle = ""
            parser.delegate = self
            parser.parse()
            let items = self.parsed, title = self.channelTitle
            DispatchQueue.main.async { self.items = items; self.feedTitle = title }
        }.resume()
    }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        current = e; text = ""
        if e == "item" || e == "entry" { inItem = true; itemTitle = ""; itemDate = nil }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            if e == "title" { itemTitle = t }
            if e == "pubDate" { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"; itemDate = f.date(from: t) }
            if e == "updated" || e == "published" { itemDate = itemDate ?? ISO8601DateFormatter().date(from: t) }
            if e == "item" || e == "entry" { inItem = false; if !itemTitle.isEmpty { parsed.append(Item(title: itemTitle, date: itemDate)) } }
        } else if e == "title" && channelTitle.isEmpty {
            channelTitle = t
        }
        text = ""
    }
}
