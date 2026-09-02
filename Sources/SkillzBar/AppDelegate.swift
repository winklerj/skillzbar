import AppKit
import ServiceManagement
import SwiftUI
import SkillzBarCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = SkillStore()
    var statusItem: NSStatusItem!
    var menu = NSMenu()
    var hotkey: HotKey?
    var ctl: CtlServer?
    var panel: SearchPanelController?
    var settings: NSWindow?
    var fixedRows = 6
    var menuIsOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.shared.info("app.launch", "v\(skillzBarVersion) bundle=\(Bundle.main.bundleIdentifier ?? "bare")")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon("book.closed")
        menu.delegate = self
        statusItem.menu = menu
        store.onChange = { [weak self] in DispatchQueue.main.async { self?.panel?.refresh() } }
        registerHotkey()
        ctl = CtlServer { [weak self] req in self?.handleCtl(req) ?? JSON.string(CtlFailure(error: "app gone")) }
        DispatchQueue.global(qos: .userInitiated).async { [store] in store.rescan() }
        syncLaunchAtLogin()
    }

    func applicationWillTerminate(_ notification: Notification) { ctl = nil }

    // MARK: menu

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let plan = currentPlan()
        if plan.rows.isEmpty {
            let empty = NSMenuItem(title: store.entries.isEmpty ? "No skills found — Rescan or add roots in Settings" : "All skills hidden", action: nil, keyEquivalent: "")
            empty.isEnabled = false; menu.addItem(empty)
        }
        let nameCounts = Dictionary(plan.rows.map { ($0.entry.name, 1) }, uniquingKeysWith: +)
        for row in plan.rows {
            let key = row.shortcut.map(String.init) ?? ""
            var title = (row.reason == .pinned ? "📌 " : "") + row.entry.name
            if nameCounts[row.entry.name, default: 0] > 1 { title += "  (\(AppPaths.abbreviate(row.entry.source.rootLabel)))" }
            let item = NSMenuItem(title: title, action: #selector(copyPath(_:)), keyEquivalent: key)
            item.target = self; item.representedObject = row.entry.id.path
            item.toolTip = "\(AppPaths.abbreviate(row.entry.id.path))  ·  \(Self.size(row.entry.byteSize))\nClick: copy path   ⌥-click: copy contents"
            menu.addItem(item)
            let alt = NSMenuItem(title: title + "  — copy contents", action: #selector(copyContents(_:)), keyEquivalent: key)
            alt.target = self; alt.representedObject = row.entry.id.path
            alt.keyEquivalentModifierMask = .option; alt.isAlternate = true
            menu.addItem(alt)
        }
        menu.addItem(.separator())
        let more = NSMenuItem(title: plan.cut.isEmpty ? "Search…" : "More… (\(plan.cut.count) more)", action: #selector(showPanel), keyEquivalent: "")
        more.target = self; menu.addItem(more)
        menu.addItem(withTitle: "Rescan", action: #selector(rescan), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SkillzBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func currentPlan() -> MenuPlan {
        let mouse = NSEvent.mouseLocation
        let (height, src): (Double?, ScreenSource) = {
            if let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return (s.visibleFrame.height, .mouseScreen) }
            if let s = NSScreen.main { return (s.visibleFrame.height, .mainScreen) }
            return (nil, .fallbackDefault)
        }()
        return MenuModel.plan(store.entries, config: store.config, usage: store.usage, screenHeight: height, screenSource: src, fixedRows: fixedRows)
    }

    @objc func copyPath(_ sender: NSMenuItem) { if let p = sender.representedObject as? String { copy(SkillID(path: p), kind: .path) } }
    @objc func copyContents(_ sender: NSMenuItem) { if let p = sender.representedObject as? String { copy(SkillID(path: p), kind: .contents) } }

    /// Central copy: clipboard, usage, feedback. Returns what was copied (for ctl).
    @discardableResult
    func copy(_ id: SkillID, kind: CopyKind) -> String? {
        guard let e = store.entry(id) else { Log.shared.error("copy", "unknown skill id", paths: [id.path]); return nil }
        do {
            let text = kind == .path ? e.id.path : try store.contentsPayload(e)
            Clipboard.set(text)
            store.recordCopy(e.id, kind: kind)
            flashIcon()
            return text
        } catch { Log.shared.error("copy", error, paths: [id.path]); return nil }
    }

    func setIcon(_ symbol: String) {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "SkillzBar")
        img?.isTemplate = true
        statusItem.button?.image = img
    }
    func flashIcon() {
        setIcon("checkmark.circle.fill")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.setIcon("book.closed") }
    }

    @objc func rescan() { DispatchQueue.global(qos: .userInitiated).async { [store] in store.rescan() } }

    @objc func showPanel() {
        if panel == nil { panel = SearchPanelController(app: self) }
        panel?.show()
    }

    @objc func showSettings() {
        if settings == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "SkillzBar Settings"; w.isReleasedWhenClosed = false; w.center()
            w.contentView = NSHostingView(rootView: SettingsView(app: self))
            settings = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    @objc func copyDiagnostics() {
        Clipboard.set(Diagnostics.text(store: store) + "\n## live menu plan\n" + JSON.string(currentPlan()))
        flashIcon()
    }

    // MARK: hotkey / login

    func registerHotkey() {
        hotkey = nil
        hotkey = HotKey(spec: store.config.hotkey) { [weak self] in self?.showPanel() }
    }

    func syncLaunchAtLogin() {
        guard Bundle.main.bundleIdentifier != nil else {
            if store.config.launchAtLogin { Log.shared.warn("login", "launchAtLogin requested but running as bare executable; install the .app bundle") }
            return
        }
        let svc = SMAppService.mainApp
        do {
            if store.config.launchAtLogin, svc.status != .enabled { try svc.register(); Log.shared.info("login", "registered") }
            if !store.config.launchAtLogin, svc.status == .enabled { try svc.unregister(); Log.shared.info("login", "unregistered") }
        } catch { Log.shared.error("login", error) }
    }

    // MARK: ctl

    func handleCtl(_ req: CtlRequest) -> String {
        struct OK<T: Encodable>: Encodable { let ok = true; let result: T }
        func ok<T: Encodable>(_ v: T) -> String { JSON.string(OK(result: v)) }
        switch req.command {
        case "ping":
            struct Ping: Encodable { let pid: Int32; let version: String }
            return ok(Ping(pid: getpid(), version: skillzBarVersion))
        case "status": return ok(store.status())
        case "list":
            let c = store.config
            return ok(store.entries.filter { req.all == true || c.visibility(of: $0.id) != .hidden })
        case "menu": return ok(currentPlan())
        case "panel":
            struct PanelView: Encodable { let groupByRoot: Bool; let groups: [String: [SkillEntry]]; let rows: [MenuRow] }
            let rows = MenuModel.ordered(store.entries, config: store.config, usage: store.usage)
            let groups = Dictionary(grouping: rows.map(\.entry), by: { $0.source.rootLabel })
            return ok(PanelView(groupByRoot: store.config.groupByRoot, groups: groups, rows: rows))
        case "rescan": return ok(store.rescan())
        case "show": showPanel(); return ok("panel shown")
        case "hide": panel?.hide(); return ok("panel hidden")
        case "open-menu":
            DispatchQueue.main.async { [self] in statusItem.button?.performClick(nil) }   // async: menu tracking blocks
            return ok("menu opening")
        case "close-menu": menu.cancelTracking(); return ok("menu closed")
        case "ui":
            // Programmatic UI state, since screenshots need Screen Recording permission.
            struct UI: Encodable { let statusItemOnScreen: Bool; let statusItemFrame: [Double]; let iconSymbol: String?; let menuOpen: Bool; let panelVisible: Bool; let panelFrame: [Double]?; let panelQuery: String?; let panelSelected: Int?; let panelRows: [String]?; let settingsVisible: Bool; let hotkey: String; let loginItemStatus: String }
            let f = statusItem.button?.window?.frame ?? .zero
            let pf = panel?.panel.frame
            return ok(UI(statusItemOnScreen: f.width > 0 && NSScreen.screens.contains { $0.frame.intersects(f) },
                         statusItemFrame: [f.origin.x, f.origin.y, f.width, f.height], iconSymbol: statusItem.button?.image?.name(),
                         menuOpen: menu.highlightedItem != nil || menuIsOpen, panelVisible: panel?.panel.isVisible ?? false,
                         panelFrame: pf.map { [$0.origin.x, $0.origin.y, $0.width, $0.height] },
                         panelQuery: panel?.model.query, panelSelected: panel?.model.selected, panelRows: panel?.model.rows.map(\.entry.name),
                         settingsVisible: settings?.isVisible ?? false, hotkey: store.config.hotkey.display,
                         loginItemStatus: Bundle.main.bundleIdentifier == nil ? "bare-executable" : "\(SMAppService.mainApp.status.rawValue) (0=notRegistered 1=enabled 2=requiresApproval 3=notFound)"))
        case "key":
            guard let p = panel, p.panel.isVisible else { return JSON.string(CtlFailure(error: "panel not shown; run `ctl show` first")) }
            for tok in (req.arg ?? "").split(separator: " ") { p.synthesize(String(tok)) }
            return ok("sent")
        case "errors": return ok(Log.shared.tail(50, level: "error"))
        case "copy":
            guard let q = req.arg else { return JSON.string(CtlFailure(error: "copy needs a skill")) }
            do {
                let e = try store.resolve(q)
                guard let text = copy(e.id, kind: req.contents == true ? .contents : .path) else { return JSON.string(CtlFailure(error: "copy failed; see errors")) }
                return ok(["skill": e.name, "path": e.id.path, "clipboardChars": String(text.count)])
            } catch { return JSON.string(CtlFailure(error: "\(error)")) }
        default: return JSON.string(CtlFailure(error: "unknown command \(req.command)"))
        }
    }

    static func size(_ b: Int64) -> String { b < 1024 ? "\(b) B" : String(format: "%.1f KB", Double(b) / 1024) }
}
