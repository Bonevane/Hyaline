// Mood widgets: a phrase for the time of day.

import SwiftUI
import AppKit

enum Mood {
    static var phrases: [String] { UserDefaults.standard.stringArray(forKey: "moodPhrases") ?? ["damn i forgot", "not today", "one thing at a time", "drink water"] }
}

struct MoodPhrase: View {
    var body: some View {
        Text(Mood.phrases.first ?? "")
            .font(.custom("Helvetica Neue", size: 47).weight(.medium)).tracking(-1.2)
            .minimumScaleFactor(0.4).lineLimit(1).multilineTextAlignment(.center)
            .blur(radius: 0.55)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MoodSerif: View {
    var body: some View {
        Text(Mood.phrases.first.map { $0.prefix(1) == $0.prefix(1).lowercased() ? $0 + "." : $0 } ?? "")
            .font(.custom("New York", size: 40).italic())
            .minimumScaleFactor(0.4).lineLimit(2).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MoodPoster: View {
    var body: some View {
        let words = (Mood.phrases.first ?? "").split(separator: " ").map(String.init)
        VStack(alignment: .leading, spacing: -10) {
            Spacer(minLength: 0)
            Text(words.first ?? "").font(.custom("Helvetica Neue", size: 96).weight(.heavy))
            Text(words.dropFirst().joined(separator: " ")).font(.custom("Helvetica Neue", size: 96).weight(.light))
        }
        .tracking(-4).minimumScaleFactor(0.3).lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

struct MoodTicker: View {
    // Scrolls on a 20 fps timeline. @State would be simpler, but its macro plugin
    // isn't in the Command Line Tools.
    @ObservedObject var power = PowerMode.shared
    var body: some View {
        let text = Mood.phrases.joined(separator: "  ·  ") + "  ·  "
        let font = NSFont(name: "HelveticaNeue-Medium", size: 30) ?? .systemFont(ofSize: 30, weight: .medium)
        let width = NSAttributedString(string: text, attributes: [.font: font, .kern: -0.6]).size().width
        TimelineView(.animation(minimumInterval: PowerMode.shared.onBattery ? 1.0 / 10 : 1.0 / 20)) { ctx in
            let offset = -CGFloat((ctx.date.timeIntervalSinceReferenceDate * 18).truncatingRemainder(dividingBy: Double(width)))
            HStack(spacing: 0) {
                Text(text).font(Font(font)).tracking(-0.6).fixedSize()
                Text(text).font(Font(font)).tracking(-0.6).fixedSize()
            }
            .offset(x: offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clipped()
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .padding(.horizontal, -Metrics.padding)
    }
}
