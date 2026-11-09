// The Updates window: what's new, download progress, and install. Taken from Bridge's
// Settings › Updates.

import AppKit
import SwiftUI

private func megabytes(_ bytes: Int64) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_048_576)
}

struct UpdatesView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            Section {
                status
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
                HStack {
                    Text(lastChecked).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { updater.check(manual: true) }
                        .disabled(updater.state == .checking)
                }
            } footer: {
                Text("Updates come from Hyaline's releases on GitHub. Each one is checked against its published checksum and Hyaline's signature before it's installed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var lastChecked: String {
        guard let date = updater.lastChecked else { return "Not checked yet" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Last checked \(f.localizedString(for: date, relativeTo: Date()))"
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle, .upToDate:
            line("checkmark.circle.fill", "Hyaline \(Updater.currentVersion)", "Up to date", .green)
        case .checking:
            HStack { Text("Checking for updates…"); Spacer(); ProgressView().controlSize(.small) }
        case .available(let r):
            versionLine(r)
            notes(r)
            HStack {
                Spacer()
                Button("Download Update") { updater.download() }.keyboardShortcut(.defaultAction)
            }
        case .downloading(let r, let done, let total, let rate):
            versionLine(r)
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            HStack {
                Text("\(megabytes(done)) of \(megabytes(total))" + (rate > 0 ? " · \(megabytes(rate))/s" : ""))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Pause") { updater.pause() }
                Button("Cancel") { updater.cancel() }
            }
        case .paused(let r, let done, let total, let reason):
            versionLine(r)
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            HStack {
                Text(reason ?? "Paused at \(megabytes(done)) of \(megabytes(total))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Resume") { updater.download() }
                Button("Cancel") { updater.cancel() }
            }
        case .verifying(let r):
            versionLine(r)
            HStack { Text("Checking the download…").foregroundStyle(.secondary); Spacer(); ProgressView().controlSize(.small) }
        case .ready(let r):
            versionLine(r)
            notes(r)
            Text(updater.installBlocker ?? "Downloaded and checked. Installing quits Hyaline, replaces it and opens the new version. Your widgets stay where they are.")
                .font(.caption).foregroundStyle(updater.installBlocker == nil ? Color.secondary : Color.orange)
            HStack {
                Spacer()
                Button("Install and Relaunch") { updater.install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(updater.installBlocker != nil)
            }
        case .installing(let r):
            versionLine(r)
            HStack { Text("Installing… Hyaline will reopen by itself.").foregroundStyle(.secondary); Spacer(); ProgressView().controlSize(.small) }
        case .failed(let message, let r):
            if let r { versionLine(r) }
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if r != nil {
                    Button("Get It from GitHub") { updater.revealDownload() }
                    Button("Try Again") { updater.download() }
                } else {
                    Button("Try Again") { updater.check(manual: true) }
                }
            }
        }
    }

    private func line(_ icon: String, _ title: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            Label(title, systemImage: icon).labelStyle(TintedIcon(tint: tint))
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func versionLine(_ r: Updater.Release) -> some View {
        line("arrow.down.circle.fill", "Hyaline \(r.version)", "You have \(Updater.currentVersion)", .accentColor)
    }

    /// The release notes, as GitHub's Markdown, folded away by default.
    @ViewBuilder private func notes(_ r: Updater.Release) -> some View {
        if !r.notes.isEmpty {
            DisclosureGroup("What's new") {
                Text((try? AttributedString(markdown: r.notes,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(r.notes))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }
}

private struct TintedIcon: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.icon.foregroundStyle(tint); configuration.title }
    }
}

/// The window, opened from the menu bar.
final class UpdatesWindow {
    private var window: NSWindow?

    @MainActor func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: UpdatesView(updater: .shared)))
            w.title = "Hyaline Updates"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
