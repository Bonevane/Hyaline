// Per-widget settings, saved with the layout.

import SwiftUI
import AppKit

/// Per-widget settings (note text, script command, GitHub user, feed URL) and the
/// sources that depend on them.
final class WidgetConfig: ObservableObject {
    @Published var values: [String: String]
    lazy var script = ScriptSource(command: values["command"] ?? "")
    lazy var github = GitHubSource(user: values["user"] ?? "")
    lazy var feed = FeedSource(url: values["url"] ?? "")
    init(values: [String: String] = [:]) { self.values = values }
    func set(_ key: String, _ value: String) {
        values[key] = value
        switch key {
        case "command": script.command = value
        case "user": github.user = value
        case "url": feed.url = value
        default: break
        }
    }
}

/// Shown in place of content until the user grants access.
struct NeedsAccess: View {
    let what: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill").font(.system(size: 18)).foregroundStyle(secondary)
            Text("Allow \(what) access for Hyaline in System Settings › Privacy & Security.")
                .font(.system(size: 12)).foregroundStyle(secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
