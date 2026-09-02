# SkillzBar

A macOS menu bar app for the agent skills you don't want loaded into every session.

Click the icon, click a skill, and the absolute path to its `SKILL.md` is on your clipboard. Option-click and you get the path plus the whole file. Hit ⌥⌘P and fuzzy-search all of them without touching the mouse. Or skip the UI entirely from a shell with `skillzbar cat <name> | pbcopy`.

Spec: [docs/SPEC.md](docs/SPEC.md).

## The problem, in my own words

I write a lot of [skills](https://agentskills.io/specification). A `SKILL.md` is the cheapest way I know to make a coding agent behave like it has done a task a hundred times: how I like commit messages, how to write a diary entry, how to rank research sources, how to set up a Swift package the way I want it. Every one of them earned its place by saving me from re-explaining something.

Then I noticed what they were costing me.

**Every skill in `~/.claude/skills` or `~/.codex/skills` is read into every session.** Not the full body, but the name and description of each one, so the agent can decide whether to trigger it. Forty skills is forty descriptions in the system prompt before I have typed a word. That is context I am paying for on every turn, and it is attention the model is spending deciding whether my "conference video assembly" skill applies to a bug fix in a Makefile. It does not. It never will. But it is there, every session, forever, because that is where skills live.

So I had two bad options. Keep everything hot and accept the bloat and the occasional bizarre mis-trigger. Or prune the folder down to the five skills I use daily and lose the other thirty-five somewhere in a `~/skills-archive` directory I would never look at again.

What I actually wanted was a third state. Not hot. Not deleted. **Cold**: on disk, findable in two seconds, and injected into a session only when I decide it is relevant.

## Why the clipboard

The insight that made this simple is that skills are already designed to be pulled in by path. Claude Code and Codex both read files the moment you paste a path into the prompt. So "activate a cold skill" is really just "get the path onto the clipboard, fast". No plugin, no MCP server, no integration with any specific agent. It works with whatever tool I am using this month and whatever I am using next month.

Two flavors, because there are two situations:

- **Click → path.** I am in an interactive session, the agent has file access, and I want to say "use this" without spending tokens on the content until it actually reads it.
- **⌥-click → path + contents.** I am in a web chat, a code review comment, a different machine over SSH, or anywhere the agent cannot read my disk. The first line is still the bare path so the agent knows where the file lives when it references it later.

## Why a menu bar app and not a shell alias

Because I tried the alias first. `cat ~/skillz/*/SKILL.md | fzf` works until you have skills in four roots, two of which are symlink farms into plugin directories, and three of which have a `research-ranker` that differs by a single line. Then you want:

- **Dedup that is actually correct.** Same inode is the same file. Same size is a candidate; only then does it hash. Different bytes with the same name stay separate and get disambiguated by root in the menu, because the version in `~/.codex/skills` and the version in `~/.claude/skills` diverged for a reason and I want to see which one I am grabbing.
- **Ordering by what I actually use.** The menu shows the top N that fit on the current screen, most-used first, with `⌘1`–`⌘9` on the first nine. After a week the menu is the five things I reach for, and the other forty are one keystroke away in the search panel.
- **Pin and hide.** Some skills I want at the top regardless of frequency. Some I want to keep on disk but never see.
- **A scan that is invisible.** Forty-nine skills across four roots scans in single-digit milliseconds using `getattrlistbulk`, so "Rescan" is something you press without thinking about it.

## Skill mode

The same binary is also a CLI. I call it **skill mode**, and the important thing about it is who it is *not* for.

The agent never learns that SkillzBar exists. Nothing about it goes into `CLAUDE.md` or `AGENTS.md`, and I do not explain it in a session either. Either one would be the original problem again, just smaller: a standing line in every context window advertising a tool the agent rarely needs. The agent only ever sees what lands in the prompt, a bare path or a path plus contents, and it already knows what to do with both.

Skill mode is the terminal-side way to produce that paste:

```bash
skillzbar cat diary | pbcopy       # same as ⌥-click, without leaving the shell
skillzbar path diary               # same as click
skillzbar find rank                # fuzzy candidates as JSON, when I forget the name
skillzbar list --json
```

It composes the way a Unix tool does: into a prompt file, into a heredoc for a headless run, into a script that assembles a session from three cold skills. This is skill mode: **code mode**, but for skills. Cold for me, cold for the agent, and warm the moment I ask.

## The part I insist on: an agent can debug it without me

I build tools with agents now, and the thing that slows that down most is "the app looks wrong" being unverifiable from a terminal. This is the one place an agent does talk to SkillzBar: not the agent doing my work, but the one fixing the app. It gets everything over a local socket:

```bash
skillzbar ctl ui             # is the status item on screen, is the panel visible, which row is selected
skillzbar ctl menu           # exactly what the quick menu will show, and why each row is there
skillzbar ctl key "dia @down @return"   # drive the search panel with synthesized keys, then pbpaste
skillzbar ctl copy diary --contents
skillzbar diagnostics        # config, last scan, stale pins, recent errors, all in one paste
```

When something breaks, **Copy Diagnostics** in the menu puts a complete report on the clipboard: file and line of every recent error, the paths involved, the config in effect. I paste it into a coding session and the fix usually arrives before I have finished describing the symptom. And the agent verifies its own fix by driving the UI and reading the clipboard, no screenshots, no human in the loop.

## Who this is for

You, if you have more skills than you use daily, you work in more than one agent, and you are tired of choosing between context bloat and forgetting what you built. It is a personal tool with sane defaults and no cloud anything. Everything lives in `~/Library/Application Support/SkillzBar` and a JSON-lines log.

## Use

- **Click** the menu bar icon → skills list. **Click** a skill: its `SKILL.md` path is on the clipboard. **⌥-click**: path line + blank line + full contents. `⌘1`–`⌘9` pick the top rows while the menu is open.
- **⌥⌘P** (configurable) → search panel. Type to filter, `↑↓⏎`, `⌥⏎` for contents, `1`–`9` for the top rows. Right-click a row to pin / hide / reveal.
- Menu → **Settings…** for roots, manual files, excludes, hotkey, launch at login. **Rescan** after changing files on disk.
- Menu → **Copy Diagnostics** when something is wrong; paste it to a coding agent.

Default roots: `~/skillz` (your cold folder), `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`. Move skills out of the hot folders into `~/skillz` and they stop loading automatically but stay one click away.

## Skill mode CLI reference

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

Requires Xcode command line tools (Swift 6 toolchain), macOS 14+. No Xcode project; SwiftPM and a Makefile.

```bash
make test       # unit tests
make run        # build release, assemble build/SkillzBar.app, launch
make install    # ~/Applications/SkillzBar.app + ~/.local/bin/skillzbar
```

Files: config `~/Library/Application Support/SkillzBar/config.json`, log `~/Library/Logs/SkillzBar/skillzbar.jsonl`.

## License

Apache License 2.0. See [LICENSE](LICENSE).
