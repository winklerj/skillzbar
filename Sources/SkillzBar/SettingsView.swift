import AppKit
import SwiftUI
import SkillzBarCore

struct SettingsView: View {
    unowned let app: AppDelegate
    @State private var cfg: Config
    @State private var excludeNamesText: String
    @State private var excludePrefixesText: String
    @State private var saved = false

    init(app: AppDelegate) {
        self.app = app
        let c = app.store.config
        _cfg = State(initialValue: c)
        _excludeNamesText = State(initialValue: c.excludeDirNames.joined(separator: "\n"))
        _excludePrefixesText = State(initialValue: c.excludePathPrefixes.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("Scan roots") {
                ForEach(cfg.roots.indices, id: \.self) { i in
                    HStack {
                        Text(cfg.roots[i].path).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Picker("", selection: $cfg.roots[i].kind) {
                            Text("Skills (SKILL.md)").tag(ContentKind.skill)
                            Text("Commands (*.md)").tag(ContentKind.command)
                        }.labelsHidden().frame(width: 170)
                        Button(role: .destructive) { cfg.roots.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("Add Skills Folder…") { addRoot(kind: .skill) }
                    Button("Add Commands Folder…") { addRoot(kind: .command) }
                }
            }
            Section("Cold folder (⇧⏎ / ⇧-click moves here; commands go under commands/)") {
                TextField("~/skillz", text: $cfg.coldRoot).font(.body.monospaced())
            }
            Section("Manual files (SKILL.md, or a single command .md)") {
                pathList($cfg.manualSkills, addTitle: "Add File…", directories: false)
            }
            Section("Excludes") {
                LabeledContent("Directory names") { TextEditor(text: $excludeNamesText).font(.body.monospaced()).frame(height: 70) }
                LabeledContent("Path prefixes") { TextEditor(text: $excludePrefixesText).font(.body.monospaced()).frame(height: 70) }
            }
            Section("Menu") {
                Stepper("Max quick-menu rows: \(cfg.maxQuickRows)", value: $cfg.maxQuickRows, in: 3...40)
                Toggle("Group by source root in search panel", isOn: $cfg.groupByRoot)
            }
            Section("Hotkey (opens search panel)") {
                HStack {
                    Toggle("⌃", isOn: $cfg.hotkey.control); Toggle("⌥", isOn: $cfg.hotkey.option)
                    Toggle("⇧", isOn: $cfg.hotkey.shift); Toggle("⌘", isOn: $cfg.hotkey.command)
                    TextField("key", text: $cfg.hotkey.key).frame(width: 60)
                        .onChange(of: cfg.hotkey.key) { _, v in if v.count > 1 { cfg.hotkey.key = String(v.last!) } }
                    Text(cfg.hotkey.display).font(.body.monospaced()).foregroundStyle(.secondary)
                }.toggleStyle(.button)
            }
            Section("System") {
                Toggle("Launch at login", isOn: $cfg.launchAtLogin)
                if Bundle.main.bundleIdentifier == nil { Text("Running as a bare executable: login item needs the installed .app").font(.caption).foregroundStyle(.orange) }
                LabeledContent("Config") { Text(AppPaths.abbreviate(AppPaths.configFile)).font(.caption.monospaced()).textSelection(.enabled) }
                LabeledContent("Log") { Text(AppPaths.abbreviate(AppPaths.logFile)).font(.caption.monospaced()).textSelection(.enabled) }
            }
            HStack {
                Spacer()
                if saved { Text("Saved & rescanned").foregroundStyle(.secondary) }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 480)
    }

    func addRoot(kind: ContentKind) {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true; p.showsHiddenFiles = true
        if p.runModal() == .OK { for u in p.urls { cfg.roots.append(ScanRoot(AppPaths.abbreviate(u.path), kind: kind)) } }
    }

    @ViewBuilder
    func pathList(_ paths: Binding<[String]>, addTitle: String, directories: Bool) -> some View {
        ForEach(paths.wrappedValue.indices, id: \.self) { i in
            HStack {
                Text(paths.wrappedValue[i]).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(role: .destructive) { paths.wrappedValue.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }
        }
        Button(addTitle) {
            let p = NSOpenPanel(); p.canChooseDirectories = directories; p.canChooseFiles = !directories; p.allowsMultipleSelection = true
            p.showsHiddenFiles = true
            if p.runModal() == .OK { for u in p.urls { paths.wrappedValue.append(AppPaths.abbreviate(u.path)) } }
        }
    }

    func save() {
        cfg.excludeDirNames = excludeNamesText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        cfg.excludePathPrefixes = excludePrefixesText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let snapshot = cfg
        app.store.update { $0 = snapshot }
        app.registerHotkey()
        app.syncLaunchAtLogin()
        app.rescan()
        saved = true
    }
}
