# SkillzBar

Personal macOS menu bar app for "cold" agent skills: `SKILL.md` files you want one click away without auto-loading them into every session. Spec: [docs/SPEC.md](docs/SPEC.md).

## Use

- **Click** the menu bar icon → skills list. **Click** a skill: its `SKILL.md` path is on the clipboard. **⌥-click**: path line + blank line + full contents. `⌘1`–`⌘9` pick the top rows while the menu is open.
- **⌥⌘P** (configurable) → search panel. Type to filter, `↑↓⏎`, `⌥⏎` for contents, `1`–`9` for the top rows. Right-click a row to pin / hide / reveal.
- Menu → **Settings…** for roots, manual files, excludes, hotkey, launch at login. **Rescan** after changing files on disk.
- Menu → **Copy Diagnostics** when something is wrong; paste it to a coding agent.

## Agent CLI ("code mode for skills")

```bash
skillzbar cat diary          # "<path>\n\n<contents>" on stdout
skillzbar path diary
skillzbar find rank          # fuzzy JSON candidates
skillzbar list --json
skillzbar scan --json        # entries, merges, skips, timings
skillzbar status --json      # config, last scan, stale pins, recent errors
skillzbar ctl menu           # what the running app's quick menu will show, and why
skillzbar ctl copy diary --contents
skillzbar ctl ui              # status item on screen? panel visible? menu open?
skillzbar ctl show|hide|open-menu|close-menu   # drive the UI for verification
skillzbar ctl key "dia @down @return"           # synthesize keys into the panel, then pbpaste
```

## Build

```bash
make test       # unit tests
make run        # build release, assemble build/SkillzBar.app, launch
make install    # ~/Applications/SkillzBar.app + ~/.local/bin/skillzbar
```

Files: config `~/Library/Application Support/SkillzBar/config.json`, log `~/Library/Logs/SkillzBar/skillzbar.jsonl`.
