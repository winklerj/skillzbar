import AppKit
import SwiftUI
import SkillzBarCore

final class PanelModel: ObservableObject {
    @Published var query = ""
    @Published var selected = 0
    @Published var showHidden = false
    @Published var entries: [SkillEntry] = []
    @Published var config = Config.defaults
    @Published var usage = Usage()

    var rows: [MenuRow] {
        let base = MenuModel.ordered(entries, config: config, usage: usage)
        let pool = showHidden ? base + entries.filter { config.visibility(of: $0.id) == .hidden }.map { MenuRow(entry: $0, reason: .alphabetical, shortcut: nil) } : base
        if query.isEmpty { return pool.enumerated().map { i, r in MenuRow(entry: r.entry, reason: r.reason, shortcut: i < 9 ? i + 1 : nil) } }
        let ranked = Fuzzy.rank(query, entries: pool.map(\.entry))
        return ranked.enumerated().map { i, r in MenuRow(entry: r.entry, reason: .alphabetical, shortcut: i < 9 ? i + 1 : nil) }
    }
    /// Grouped by source root when enabled; keeps ordering inside groups.
    var groups: [(label: String, rows: [MenuRow])] {
        let rs = rows
        guard config.groupByRoot else { return [("", rs)] }
        var order: [String] = []; var map: [String: [MenuRow]] = [:]
        for r in rs { let k = AppPaths.abbreviate(r.entry.source.rootLabel); if map[k] == nil { order.append(k) }; map[k, default: []].append(r) }
        return order.map { ($0, map[$0]!) }
    }
}

/// Intercepts keyDown at the window level so navigation/copy keys work regardless of TextField focus,
/// and so `ctl key` can exercise the exact same path with synthesized events.
final class KeyPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let onKey, onKey(event) { return }
        super.sendEvent(event)
    }
}

final class SearchPanelController {
    unowned let app: AppDelegate
    let model = PanelModel()
    let panel: KeyPanel

    init(app: AppDelegate) {
        self.app = app
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: SearchView(model: model, controller: self))
        panel.onKey = { [weak self] e in self?.handleKey(e) ?? false }
    }

    /// Returns true if consumed. Digits act as shortcuts only while the query is empty.
    func handleKey(_ e: NSEvent) -> Bool {
        let option = e.modifierFlags.contains(.option)
        let rows = model.rows
        switch e.keyCode {
        case 125: model.selected = min(model.selected + 1, max(0, rows.count - 1)); return true   // ↓
        case 126: model.selected = max(model.selected - 1, 0); return true                         // ↑
        case 53: hide(); return true                                                                // esc
        case 36, 76:                                                                                // return / enter
            guard model.selected < rows.count else { return true }
            copy(rows[model.selected], kind: option ? .contents : .path); return true
        default:
            if model.query.isEmpty, let ch = e.charactersIgnoringModifiers, let d = Int(ch), (1...9).contains(d) {
                if d <= rows.count { copy(rows[d - 1], kind: option ? .contents : .path) }
                return true
            }
            return false
        }
    }

    /// For `ctl key`: "@down" "@up" "@return" "@opt-return" "@esc" or literal characters to type.
    func synthesize(_ token: String) {
        func send(_ code: UInt16, _ chars: String, mods: NSEvent.ModifierFlags = []) {
            guard let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: panel.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                            isARepeat: false, keyCode: code) else { return }
            panel.sendEvent(ev)
        }
        switch token {
        case "@down": send(125, "")
        case "@up": send(126, "")
        case "@esc": send(53, "\u{1b}")
        case "@return": send(36, "\r")
        case "@opt-return": send(36, "\r", mods: .option)
        default: for ch in token { send(0, String(ch)) }
        }
    }

    func refresh() {
        model.entries = app.store.entries; model.config = app.store.config; model.usage = app.store.usage
        model.selected = min(model.selected, max(0, model.rows.count - 1))
    }

    func show() {
        refresh()
        model.query = ""; model.selected = 0
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2 + f.height * 0.15))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func hide() { panel.orderOut(nil) }

    func copy(_ row: MenuRow, kind: CopyKind) {
        app.copy(row.entry.id, kind: kind)
        hide()
    }
    func toggle(_ row: MenuRow, _ v: Visibility) {
        app.store.update { c in c.setVisibility(c.visibility(of: row.entry.id) == v ? nil : v, for: row.entry.id) }
        refresh()
    }
}

struct SearchView: View {
    @ObservedObject var model: PanelModel
    let controller: SearchPanelController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search skills — ⏎ copy path · ⌥⏎ copy contents · 1–9 quick copy", text: $model.query)
                    .textFieldStyle(.plain).font(.title3).focused($focused)
                    .onChange(of: model.query) { _, _ in model.selected = 0 }
                Toggle("hidden", isOn: $model.showHidden).toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
                Toggle("group", isOn: Binding(get: { model.config.groupByRoot }, set: { v in controller.app.store.update { $0.groupByRoot = v }; controller.refresh() }))
                    .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
            }.padding(12)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(model.groups.enumerated()), id: \.offset) { _, g in
                        if !g.label.isEmpty { Text(g.label).font(.caption).foregroundStyle(.secondary).padding(.top, 4) }
                        ForEach(g.rows, id: \.entry.id) { row in
                            rowView(row, index: model.rows.firstIndex { $0.entry.id == row.entry.id } ?? 0).id(row.entry.id)
                        }
                    }
                }
                .listStyle(.plain)
                .onChange(of: model.selected) { _, i in if i < model.rows.count { proxy.scrollTo(model.rows[i].entry.id) } }
            }
            Divider()
            HStack {
                Text("\(model.rows.count) skills").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(model.config.hotkey.display).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }.padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(minWidth: 480, minHeight: 300)
        .onAppear { focused = true }
        .onExitCommand { controller.hide() }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard model.query.isEmpty, let d = Int(press.characters), d >= 1, d <= model.rows.count else { return .ignored }
            controller.copy(model.rows[d - 1], kind: press.modifiers.contains(.option) ? .contents : .path); return .handled
        }
    }

    @ViewBuilder
    func rowView(_ row: MenuRow, index: Int) -> some View {
        let vis = model.config.visibility(of: row.entry.id)
        HStack(spacing: 8) {
            Text(row.shortcut.map { "\($0)" } ?? "").font(.caption.monospaced()).foregroundStyle(.tertiary).frame(width: 14)
            if vis == .pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.entry.name).fontWeight(index == model.selected ? .semibold : .regular)
                    .foregroundStyle(vis == .hidden ? .secondary : .primary)
                Text(AppPaths.abbreviate(row.entry.id.path)).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if case .usage(let c) = row.reason { Text("×\(c)").font(.caption2).foregroundStyle(.tertiary) }
            Text(AppDelegate.size(row.entry.byteSize)).font(.caption2.monospaced()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(index == model.selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { controller.copy(row, kind: NSEvent.modifierFlags.contains(.option) ? .contents : .path) }
        .contextMenu {
            Button("Copy Path") { controller.copy(row, kind: .path) }
            Button("Copy Contents") { controller.copy(row, kind: .contents) }
            Divider()
            Button(vis == .pinned ? "Unpin" : "Pin") { controller.toggle(row, .pinned) }
            Button(vis == .hidden ? "Unhide" : "Hide") { controller.toggle(row, .hidden) }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.entry.id.path)]) }
        }
    }
}
