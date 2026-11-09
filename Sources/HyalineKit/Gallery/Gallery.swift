import AppKit
import SwiftUI

// The widget gallery: every widget, live, at its real size, grouped by kind.
// Click a widget to add it, drag it onto the desktop to place it, or use the pencil to
// pick its style (Glass, Frosted, Clear) and options before adding.

/// What a widget will be added with: chosen in the edit popup, shown in the previews.
struct WidgetDraft: Equatable {
    var look: WidgetLook
    var values: [String: String]
    var fontWeight: Double?

    static func initial(for kind: WidgetKind) -> WidgetDraft {
        var values: [String: String] = [:]
        // Configurable widgets start with something to show, so the preview isn't empty.
        // What you see is what gets added; the edit popup changes it.
        for setting in kind.settings {
            switch setting.key {
            case "url": values["url"] = "https://www.apple.com/newsroom/rss-feed.rss"
            case "command": values["command"] = "date"
            default: break
            }
        }
        for toggle in kind.toggles { values[toggle.key] = toggle.defaultOn ? "1" : "0" }
        return WidgetDraft(look: kind.look, values: values, fontWeight: nil)
    }
}

final class GalleryModel: ObservableObject {
    @Published var group = Registry.groups.first ?? ""
    @Published var search = ""
    @Published var drafts: [String: WidgetDraft] = [:]
    let context: WidgetContext
    let surface: () -> SurfaceSettings
    /// Adds a widget; nil origin = the middle of the screen, moved to a free spot.
    let add: (WidgetKind, WidgetDraft, CGPoint?) -> WidgetPanel
    weak var window: NSWindow?

    init(context: WidgetContext, surface: @escaping () -> SurfaceSettings,
         add: @escaping (WidgetKind, WidgetDraft, CGPoint?) -> WidgetPanel) {
        self.context = context; self.surface = surface; self.add = add
    }

    func draft(_ kind: WidgetKind) -> WidgetDraft { drafts[kind.id] ?? .initial(for: kind) }
    func binding(_ kind: WidgetKind) -> Binding<WidgetDraft> {
        Binding(get: { self.draft(kind) }, set: { self.drafts[kind.id] = $0 })
    }

    var shown: [WidgetKind] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return Registry.kinds.filter { $0.group == group } }
        return Registry.kinds.filter { "\($0.group) \($0.name)".lowercased().contains(query) }
    }
}

enum GallerySymbols {
    static let byGroup: [String: String] = [
        "Clock": "clock", "Mood": "quote.opening", "CPU and system": "cpu", "Memory": "memorychip",
        "Battery": "battery.75percent", "Network": "wifi", "Storage": "internaldrive", "Energy": "bolt",
        "Time": "sun.horizon", "Calendar": "calendar", "Reminders": "checklist", "Weather": "cloud.sun",
        "Now Playing": "music.note", "Temperatures": "thermometer.medium", "Notes": "note.text",
        "Scripts and web": "chevron.left.forwardslash.chevron.right",
    ]
}

struct GalleryView: View {
    @ObservedObject var model: GalleryModel

    var body: some View {
        NavigationSplitView {
            List(Registry.groups, id: \.self, selection: Binding(get: { model.group }, set: { model.group = $0 ?? model.group; model.search = "" })) { group in
                Label(group, systemImage: GallerySymbols.byGroup[group] ?? "square")
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.search.isEmpty ? model.group : "Results").font(.system(size: 20, weight: .semibold))
                    Text("Click a widget to add it, or drag it where you want it on the desktop.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 30, lineSpacing: 26) {
                        ForEach(model.shown, id: \.id) { kind in
                            GalleryCard(kind: kind, model: model)
                        }
                    }
                    .padding(.top, 28)
                    if model.shown.isEmpty {
                        Text("No widgets match “\(model.search)”.").foregroundStyle(.secondary).padding(.top, 28)
                    }
                }
                .padding(.horizontal, 36).padding(.vertical, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .searchable(text: $model.search, placement: .sidebar, prompt: "Search")
    }
}

/// Rows that wrap, top-aligned, like Apple's gallery.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1000
        let all = rows(width, subviews)
        let height = all.reduce(0) { $0 + ($1.map(\.1.height).max() ?? 0) } + lineSpacing * CGFloat(max(all.count - 1, 0))
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            var x = bounds.minX
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += (row.map(\.1.height).max() ?? 0) + lineSpacing
        }
    }
}

struct GalleryCard: View {
    let kind: WidgetKind
    @ObservedObject var model: GalleryModel
    @StateObject private var state = CardState()

    var body: some View {
        let draft = model.draft(kind)
        VStack(spacing: 8) {
            WidgetPreview(kind: kind, draft: draft, model: model)
                .frame(width: kind.size.cg.width, height: kind.size.cg.height)
                .overlay(alignment: .topLeading) {
                    if state.hovering || state.editing {
                        badge("plus.circle.fill", help: "Add to desktop") { _ = model.add(kind, draft, nil) }
                            .offset(x: -9, y: -9)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if state.hovering || state.editing {
                        badge("pencil.circle.fill", help: "Style and options") { state.editing = true }
                            .offset(x: 9, y: -9)
                            .popover(isPresented: $state.editing, arrowEdge: .bottom) {
                                StylePopover(kind: kind, model: model, draft: model.binding(kind)) { state.editing = false }
                            }
                    }
                }
            VStack(spacing: 1) {
                Text(kind.name).font(.system(size: 12, weight: .medium))
                Text(model.search.isEmpty ? kind.size.label : "\(kind.group) · \(kind.size.label)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .onHover { state.hovering = $0 }
    }

    private func badge(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22))
                .symbolRenderingMode(.palette).foregroundStyle(.black, .white)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .buttonStyle(.plain).help(help)
    }
}

// @State needs Xcode's macro plugin, which the Command Line Tools lack: plain objects instead.
final class CardState: ObservableObject {
    @Published var hovering = false
    @Published var editing = false
}
final class PendingText: ObservableObject { @Published var text: [String: String] = [:] }

/// The edit popup: the widget in each look side by side, then its options.
struct StylePopover: View {
    let kind: WidgetKind
    @ObservedObject var model: GalleryModel
    @Binding var draft: WidgetDraft
    let done: () -> Void
    @StateObject private var pending = PendingText()

    private var scale: CGFloat {
        // Three across in about 520pt, whatever the widget's size.
        min(0.62, 150 / kind.size.cg.width, 150 / kind.size.cg.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(kind.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { commitText(); done() }.keyboardShortcut(.defaultAction)
            }
            section("Style")
            HStack(alignment: .top, spacing: 14) {
                ForEach(WidgetLook.allCases, id: \.self) { look in
                    let chosen = draft.look == look
                    VStack(spacing: 7) {
                        WidgetPreview(kind: kind, draft: { var d = draft; d.look = look; return d }(), model: model, scale: scale, interactive: false)
                            .frame(width: kind.size.cg.width * scale, height: kind.size.cg.height * scale)
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: Metrics.radius * scale + 5, style: .continuous)
                                .strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2.5))
                            .contentShape(Rectangle())
                            .onTapGesture { draft.look = look }
                        Text(look.rawValue).font(.system(size: 12, weight: chosen ? .semibold : .regular))
                            .foregroundStyle(chosen ? .primary : .secondary)
                    }
                }
            }
            if hasOptions {
                section("Options")
                VStack(spacing: 0) {
                    ForEach(Array(kind.toggles.enumerated()), id: \.offset) { i, toggle in
                        if i > 0 { Divider().padding(.leading, 12) }
                        row(toggle.title) {
                            Toggle("", isOn: Binding(get: { draft.values[toggle.key] == "1" },
                                                     set: { draft.values[toggle.key] = $0 ? "1" : "0" }))
                                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }
                    }
                    if kind.hasFontWeight {
                        if !kind.toggles.isEmpty { Divider().padding(.leading, 12) }
                        row("Font weight") {
                            Picker("", selection: Binding(get: { draft.fontWeight ?? GlassClockView.weight },
                                                          set: { draft.fontWeight = $0 == GlassClockView.weight ? nil : $0 })) {
                                ForEach([60.0, 120, 180, 250, 320, 400, 500], id: \.self) { w in
                                    Text(w == GlassClockView.weight ? "\(Int(w)) (default)" : "\(Int(w))").tag(w)
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    ForEach(Array(kind.settings.enumerated()), id: \.offset) { i, setting in
                        if i > 0 || !kind.toggles.isEmpty || kind.hasFontWeight { Divider().padding(.leading, 12) }
                        settingRow(setting)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            }
        }
        .padding(16)
        .frame(width: max(400, (kind.size.cg.width * scale + 24) * 3 + 32))
        .onDisappear(perform: commitText)
    }

    private var hasOptions: Bool { !kind.toggles.isEmpty || !kind.settings.isEmpty || kind.hasFontWeight }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func row(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack { Text(title); Spacer(); trailing() }
            .font(.system(size: 13)).padding(.horizontal, 12).frame(minHeight: 36)
    }

    /// Text settings apply when you press Return or close the popup, not on every key,
    /// since each change rebuilds the previews (and may fetch a feed).
    @ViewBuilder private func settingRow(_ setting: WidgetSetting) -> some View {
        let value = Binding(get: { pending.text[setting.key] ?? draft.values[setting.key] ?? "" },
                            set: { pending.text[setting.key] = $0 })
        VStack(alignment: .leading, spacing: 6) {
            Text(setting.prompt).font(.system(size: 12)).foregroundStyle(.secondary)
            if setting.multiline {
                TextEditor(text: value).font(.system(size: 13)).frame(height: 70)
                    .scrollContentBackground(.hidden)
            } else {
                TextField("", text: value).textFieldStyle(.roundedBorder).onSubmit(commitText)
            }
        }
        .padding(12)
    }

    private func commitText() {
        guard !pending.text.isEmpty else { return }
        for (key, value) in pending.text { draft.values[key] = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        pending.text = [:]
    }
}

/// A live widget drawn exactly as on the desktop (same glass, same content). Not
/// clickable inside: a click adds it, a drag carries a new widget out onto the desktop.
struct WidgetPreview: NSViewRepresentable {
    let kind: WidgetKind
    let draft: WidgetDraft
    let model: GalleryModel
    var scale: CGFloat = 1
    var interactive = true

    func makeNSView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        update(view)
        return view
    }
    func updateNSView(_ view: PreviewHostView, context: Context) { update(view) }

    private func update(_ view: PreviewHostView) {
        view.interactive = interactive
        view.onClick = { [kind, draft, model] in _ = model.add(kind, draft, nil) }
        view.onDragStart = { [kind, draft, model] origin in model.add(kind, draft, origin) }
        view.window_ = { [model] in model.window }
        view.fullSize = kind.size.cg
        let key = "\(scale)|\(draft.look)|\(draft.fontWeight ?? 0)|\(draft.values.sorted { $0.key < $1.key })"
        guard key != view.builtFor else { return }
        view.builtFor = key
        view.subviews.forEach { $0.removeFromSuperview() }

        let config = WidgetConfig(values: draft.values)
        var native: (() -> NSView)?
        if let make = kind.native {
            // AppKit clocks read their options from a panel; this one is never shown.
            let stand = WidgetPanel(origin: .zero, size: kind.size.cg, content: AnyView(EmptyView()), config: config)
            stand.fontWeight = draft.fontWeight
            view.stand = stand
            native = { make(stand) }
        }
        let content = kind.configured?(model.context, config) ?? kind.view?(model.context) ?? AnyView(EmptyView())
        let surface = WidgetPanel.surfaceView(look: draft.look, surface: model.surface(), size: kind.size.cg, scale: scale,
                                              content: content, native: native)
        surface.frame = NSRect(x: 0, y: 0, width: kind.size.cg.width * scale, height: kind.size.cg.height * scale)
        surface.autoresizingMask = []
        view.addSubview(surface)
    }
}

final class PreviewHostView: NSView {
    var builtFor = ""
    var stand: WidgetPanel?
    var interactive = true
    var fullSize: CGSize = .zero
    var onClick: () -> Void = {}
    var onDragStart: (CGPoint) -> WidgetPanel = { _ in fatalError() }
    var window_: () -> NSWindow? = { nil }

    private var downAt: NSPoint = .zero
    private var grab: CGPoint = .zero
    private var carried: WidgetPanel?

    override var isFlipped: Bool { true }
    // The surface is built at its final size; SwiftUI sizes this view after it's added
    // (from zero), and autoresizing would stretch the surface by that growth.
    override var autoresizesSubviews: Bool { get { false } set {} }
    override func layout() {
        super.layout()
        subviews.forEach { $0.frame = bounds }
    }
    // Nothing inside a preview takes the mouse: buttons and links in widgets stay inert.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactive else { return nil }
        return frame.contains(point) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        // Where in the widget it was grabbed, from its bottom-left (screen coordinates run up).
        let local = convert(event.locationInWindow, from: nil)
        grab = CGPoint(x: local.x, y: bounds.height - local.y)
        carried = nil
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        if carried == nil {
            guard hypot(mouse.x - downAt.x, mouse.y - downAt.y) >= 4 else { return }
            let panel = onDragStart(CGPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
            panel.level = .floating   // above the gallery while it's carried
            carried = panel
        }
        guard let panel = carried else { return }
        let raw = NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let origin = screen.map { Snapper.snap(raw, size: panel.frame.size, obstacles: panel.obstacles(), screen: $0.visibleFrame) } ?? raw
        panel.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        guard let panel = carried else {
            if hypot(NSEvent.mouseLocation.x - downAt.x, NSEvent.mouseLocation.y - downAt.y) < 4 { onClick() }
            return
        }
        carried = nil
        panel.level = WidgetPanel.desktopLevel
        // Dropped back on the gallery: cancel.
        if let window = window_(), window.frame.contains(NSEvent.mouseLocation) {
            panel.onRemove()
            return
        }
        panel.settle(fallback: panel.frame, animate: true, obstacles: panel.obstacles())
        panel.onLayoutChange()
    }
}

/// The gallery's window, opened from the menu bar.
final class GalleryWindow {
    private var window: NSWindow?
    private let model: GalleryModel

    init(model: GalleryModel) { self.model = model }

    /// Where the gallery is on screen, while it's open.
    var visibleFrame: NSRect? { window?.isVisible == true ? window?.frame : nil }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 760),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Widget Gallery"
            w.contentViewController = NSHostingController(rootView: GalleryView(model: model))
            w.setContentSize(NSSize(width: 1240, height: 760))
            w.contentMinSize = NSSize(width: 760, height: 480)
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("WidgetGallery")
            if !w.setFrameUsingName("WidgetGallery") { w.center() }
            model.window = w
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
