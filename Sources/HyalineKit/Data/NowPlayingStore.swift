// What Spotify or Music is playing, through AppleScript (asks for Automation access once per player).

import AppKit
import EventKit
import CoreLocation
import IOKit

final class NowPlayingStore: ObservableObject {
    static let shared = NowPlayingStore()
    @Published var title: String?
    @Published var artist = ""
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var artwork: NSImage?
    @Published var player = ""
    /// Where the user is dragging the seek bar (0…1), nil when not scrubbing.
    @Published var scrub: Double?
    private var polledAt = Date()
    private var artURL: String?
    private var started = false
    var isVisible: () -> Bool = { true }

    func start() {
        guard !started else { return }
        started = true
        poll()
        timer = AdaptiveTimer(ac: 2, battery: 5) { [weak self] in if self?.isVisible() ?? false { self?.poll() } }
    }
    private var timer: AdaptiveTimer?

    /// Only talks to a player that is already running, so polling never launches one.
    private var runningPlayer: String? {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if ids.contains("com.spotify.client") { return "Spotify" }
        if ids.contains("com.apple.Music") { return "Music" }
        return nil
    }

    private func poll() {
        guard !GalleryMode.on, let app = runningPlayer else { title = nil; return }
        let art = app == "Spotify" ? " & linefeed & (artwork url of current track)" : ""
        let source = """
        tell application "\(app)"
          if player state is stopped then return ""
          return (name of current track) & linefeed & (artist of current track) & linefeed & (player state as string) & linefeed & (player position as string) & linefeed & (duration of current track as string)\(art)
        end tell
        """
        var error: NSDictionary?
        guard let out = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue, !out.isEmpty else { title = nil; return }
        let parts = out.components(separatedBy: "\n")
        guard parts.count >= 5 else { return }
        player = app
        title = parts[0]; artist = parts[1]; playing = parts[2] == "playing"
        position = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        polledAt = Date()
        let d = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        duration = app == "Spotify" ? d / 1000 : d     // Spotify reports milliseconds
        if parts.count > 5, parts[5] != artURL, let url = URL(string: parts[5]) {
            artURL = parts[5]
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data, let img = NSImage(data: data) { DispatchQueue.main.async { self.artwork = img } }
            }.resume()
        } else if parts.count <= 5 { artwork = nil }
    }

    /// The position now, counted on from the last poll while playing.
    func livePosition(at date: Date) -> Double {
        playing ? min(position + date.timeIntervalSince(polledAt), duration) : position
    }

    func seek(to seconds: Double) {
        position = seconds; polledAt = Date()
        command("set player position to \(String(format: "%.1f", seconds))")
    }

    func command(_ verb: String) {
        guard let app = runningPlayer else { return }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"\(app)\" to \(verb)")?.executeAndReturnError(&error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.poll() }
    }
}
