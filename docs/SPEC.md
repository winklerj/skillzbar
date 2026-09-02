# SkillzBar — menu bar manager for cold agent skills

Personal macOS app. One user. Optimizes for: stay in flow, and let a coding agent build/verify/fix it without a human relaying errors.

## Problem

Skills in `~/.claude/skills` auto-load into every session. Many are rarely used but still valuable. Reaching for them today means finding the path or opening Obsidian to copy/paste. The app becomes the home for "cold" skills that live outside auto-load paths.

## Core interactions

| Action | Result |
|---|---|
| Click menu bar icon | Menu: pinned skills, then top-N by usage, then `More…`, `Rescan`, `Settings…`, `Copy Diagnostics`, `Quit` |
| Click a skill | Clipboard = absolute path to `SKILL.md` |
| Option-click a skill (alternate menu item) | Clipboard = `<absolute path>\n\n<file contents>` |
| `More…` / global hotkey | Search panel: type-to-filter over all known skills, same click/Option-click semantics, optional group-by-source-root, pin/hide toggles, subtle size column |
| Global hotkey #2 | Open the quick menu without the mouse |
| Any copy | Brief icon flash (checkmark) as feedback |

N = min(rows that fit, `max_quick_rows` config, default 20). Screen = the `NSScreen` containing `NSEvent.mouseLocation` at menu-open time (the menu opens on that display), falling back to `NSScreen.main`, falling back to a universal default of 15 rows (fits any Mac display at 22pt/row). `NSMenu` scrolls on overflow, so a wrong guess degrades gracefully. Cap exists for scan speed (selection time grows with log of item count, Hick's law), not only for fit.
Top 9 rows get key equivalents: `⌘1`–`⌘9` inside the open menu, bare `1`–`9` in the search panel (hotkey → digit → copied, no mouse).

## Discovery

- Roots (default): `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`, `~/skillz` (cold-skill folder). User adds roots or single `SKILL.md` files manually.
- Excludes (default, editable): `~/Library/**`, `**/.tmp/**`, `**/node_modules/**`, `~/.claude/plugins/**`, `~/.codex/plugins/**`, `~/.codex/.tmp/**`, `**/.git/**`.
- Rescan is manual only (menu item, CLI, or after settings change). No FS watching.
- Dedup, cheapest-first: (1) same `st_dev`+`st_ino` → hard link/same file, no read; (2) different `st_size` → cannot be duplicates, no read; (3) equal size → hash (SHA-256 via CryptoKit, hardware-accelerated on Apple Silicon, no dependency). Hashes cached in `~/Library/Application Support/SkillzBar/cache.json` keyed by `(path, size, mtime_ns, inode)`; only changed files are rehashed on rescan. Duplicates collapse to one entry; preferred path = manual > earliest-listed root. Symlinks resolved first.
- Traversal: `getattrlistbulk(2)` per directory (type + size + mtime for a whole directory in one syscall; no per-entry `stat`), excluded directories pruned at descent time (never entered), roots walked concurrently with a `TaskGroup`. Fallback `fts(3)` if `getattrlistbulk` is unavailable on a volume. Rejected: `FileManager.enumerator` (per-item `NSURL` allocation, slow), Spotlight/`NSMetadataQuery` (does not reliably index dot-directories like `~/.claude`), FSEvents (user chose manual rescan).
- No frontmatter parsing. Display name = parent directory name. Description omitted.

Baseline on this machine (2026-09-02): 2,113 `SKILL.md` under `~`; ~10 hand-authored in `~/.claude/skills`. Defaults above must yield tens, not thousands.

## Ordering (frequency)

MVP: the app records its own copy events (`skill_id`, timestamp). Order = pinned, then copy count desc, then name. Hidden skills never appear in the quick menu; visible in the search panel behind a toggle.

Post-MVP: seed counts deterministically from agent session logs:
- Claude Code: `~/.claude/projects/*/*.jsonl` — scan for known skill paths in message text.
- Codex: `~/.codex/sessions/**` — same.
Only skills already known to the app are counted.

## Agent-facing CLI ("code mode for skills")

An agent fetches a skill from the app instead of the user pasting it:
- `skillzbar find <query>` — fuzzy match over names/paths, prints candidates as JSON.
- `skillzbar cat <name|path>` — prints `<absolute path>\n\n<contents>` to stdout (same format as Option-click).
- `skillzbar path <name|path>` — prints the path only.
- `skillzbar list [--json]` — all known skills, respecting hidden unless `--all`.
These read config + cache directly (no running app required) so they work from any agent shell.

## Agent-verifiability (first-class requirement)

The same binary runs as app or CLI. Shared core library; no UI in core.

- `skillzbar scan --json` — run discovery with current config, print entries + dedup decisions + skipped paths with reasons.
- `skillzbar status --json` — version, config path, roots, exclude patterns, entry count, last scan time, last N errors.
- `skillzbar copy <id> [--contents]` — perform the copy; prints what went to clipboard.
- `skillzbar ctl <ping|status|list|menu|panel|rescan|errors|copy|show|hide|open-menu|close-menu|ui|key>` — talks to the *running* app over a Unix domain socket (`~/Library/Application Support/SkillzBar/ctl.sock`) so live state can be inspected and driven.
- `skillzbar ctl menu --json` — emits exactly what the quick menu would render: computed N, screen height used, ordered rows each with the reason it is present (pinned / usage count / name fallback), and the rows that were cut. `ctl panel --json` does the same for the search panel including grouping. This is how an agent verifies ordering/truncation without a human looking at the screen.
- `skillzbar log --tail N` — JSON-lines log at `~/Library/Logs/SkillzBar/skillzbar.jsonl`. Every error record includes: timestamp, operation, file/line, error type, message, underlying `NSError` domain/code, and relevant paths.
- Menu `Copy Diagnostics` — copies `status --json` + last 50 log lines. This is the "hand it to an agent" path.
- `make build|run|test|install` — no Xcode GUI required. `swift build` + script assembles `.app` bundle with `LSUIElement=1`. `make install` copies to `~/Applications` and registers launch-at-login from there (`SMAppService` is sensitive to bundle id and location with ad-hoc signing; verify at install time and log the result).
- Hotkey registration failures (`RegisterEventHotKey` conflicts fail silently) must be detected and logged.

## Settings (persisted JSON, `~/Library/Application Support/SkillzBar/config.json`)

- roots: [path], manual_skills: [path], exclude_dir_names: [name], exclude_path_prefixes: [path]
- pinned: [skill_id], hidden: [skill_id]
- group_by_root: bool (search panel)
- hotkey (single, default `⌥⌘P`): opens the search panel with focus in the search field, top-N rows pre-listed with `1`–`9` shortcuts, `↑↓⏎` to select, `⌥⏎` for contents. One hotkey serves both quick and search cases; the menu bar icon stays the mouse path. `⌥⌘` is a thumb chord (left hand), `P` is right hand. Conflicts detected at registration and logged; rebindable in Settings.
- launch_at_login: bool (`SMAppService`)

## Data model (invalid state unrepresentable)

```
SkillID        = canonical resolved path of the preferred SKILL.md (stable across edits)
ContentHash    = SHA-256 of contents (dedup key at scan time only; never identity)
SkillSource    = discovered(root: URL) | manual
SkillEntry     = { id, name, byteSize, contentHash, source, duplicatePaths: [URL] }
Visibility     = pinned | normal | hidden        // per SkillID, default normal
UsageRecord    = { id, copiedAt, kind: path | contents }
```

Pinned/hidden/usage are keyed by `SkillID` (path), so editing a skill keeps its state. A pinned/hidden path that disappears on rescan stays in config marked `stale` and is reported by `status --json`; it is never silently dropped.

## Stack

Swift 6.2 toolchain, Swift 5 language mode (avoids AppKit actor-isolation friction), macOS 14+. AppKit `NSStatusItem` + `NSMenu` (alternate items for Option-click). SwiftUI for the search panel and settings, hosted in an `NSPanel`. Global hotkeys via Carbon `RegisterEventHotKey` (no Accessibility permission needed). SwiftPM package with three targets: `SkillzBarCore` (library), `skillzbar` (executable: app + CLI entry), `SkillzBarCoreTests`.

## Distribution readiness

v1 is unsigned/ad-hoc, local only. Cheap hedges taken now so distribution later is packaging, not redesign:
- All file access in Core goes through a `SkillFileSystem` protocol. The v1 implementation reads paths directly; a sandboxed implementation would resolve security-scoped bookmarks. No other code changes.
- Core has no UI and no AppKit imports, so it can be consumed unchanged by an Xcode/XcodeGen app target if a signed bundle pipeline is needed.
- Intended distribution path if ever needed: Developer ID + notarization (no sandbox; CLI and socket survive). Mac App Store would additionally require sandboxing, user-granted folder access via `NSOpenPanel` bookmarks, and would break the out-of-bundle CLI/socket design; treat App Store as a redesign of the CLI story, not a packaging change.

## Out of scope (v1)

Frontmatter, FS watching, size warnings, multi-user, App Store, sandboxing.
