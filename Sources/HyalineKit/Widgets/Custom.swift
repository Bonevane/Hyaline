// Configurable widgets: note, script output, GitHub contribution grid and feed headlines.

import SwiftUI
import AppKit

struct NoteWidget: View {
    @ObservedObject var config: WidgetConfig
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WLabel(symbol: "note.text", text: "Note")
            Text(config.values["text"].flatMap { $0.isEmpty ? nil : $0 } ?? "Right-click › Edit note… to write here.")
                .font(.system(size: 15)).lineSpacing(3)
                .foregroundStyle(config.values["text"]?.isEmpty == false ? .white : secondary)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScriptWidget: View {
    @ObservedObject var config: WidgetConfig
    var body: some View { ScriptBody(source: config.script) }
}

struct ScriptBody: View {
    @ObservedObject var source: ScriptSource
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WLabel(symbol: "terminal", text: source.command.isEmpty ? "Script" : String(source.command.prefix(28)))
                Spacer()
                if let at = source.ranAt { Text(at.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(secondary) }
            }
            Text(source.command.isEmpty ? "Right-click › Set command… to run a shell command every minute." : source.output)
                .font(.system(size: 12, design: .monospaced)).lineSpacing(2)
                .foregroundStyle(source.command.isEmpty ? secondary : .white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
    }
}

struct GitHubWidget: View {
    @ObservedObject var config: WidgetConfig
    var body: some View { GitHubBody(source: config.github) }
}

struct GitHubBody: View {
    @ObservedObject var source: GitHubSource
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WLabel(symbol: "square.grid.3x3.fill", text: source.user.isEmpty ? "GitHub" : source.user)
                Spacer()
                if let t = source.total { Text("\(t) this year").font(.system(size: 11.5)).foregroundStyle(secondary) }
            }
            if source.user.isEmpty {
                Text("Right-click › Set GitHub username…").font(.system(size: 12.5)).foregroundStyle(secondary).frame(maxHeight: .infinity)
            } else {
                // Last 19 weeks, filling the widget (the review asked for no empty band).
                Canvas { gc, size in
                    let weeks = 19, levels = Array(source.levels.suffix(weeks * 7))
                    let gap: CGFloat = 3, cell = min((size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks), (size.height - gap * 6) / 7)
                    for (i, level) in levels.enumerated() {
                        let r = CGRect(x: CGFloat(i / 7) * (cell + gap), y: CGFloat(i % 7) * (cell + gap), width: cell, height: cell)
                        gc.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(.white.opacity(level == 0 ? 0.08 : 0.2 + Double(level) * 0.19)))
                    }
                }
            }
        }
    }
}

struct FeedWidget: View {
    @ObservedObject var config: WidgetConfig
    var body: some View { FeedBody(source: config.feed) }
}

struct FeedBody: View {
    @ObservedObject var source: FeedSource
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WLabel(symbol: "dot.radiowaves.up.forward", text: source.feedTitle.isEmpty ? "Feed" : String(source.feedTitle.prefix(30)))
            if source.url.isEmpty {
                Text("Right-click › Set feed URL…").font(.system(size: 12.5)).foregroundStyle(secondary).frame(maxHeight: .infinity)
            } else {
                ForEach(Array(source.items.prefix(2).enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 0.5) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        if let d = item.date { Text(d.formatted(.relative(presentation: .named))).font(.system(size: 10.5)).foregroundStyle(secondary) }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
