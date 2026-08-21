# GitNotice

An Omarchy 4 bar-widget plugin. Add the local paths of your git repos (your
notes vault, side projects, etc.) and GitNotice watches them for uncommitted
changes.

- A pill sits in the bar. It stays quiet (✓) when everything is clean and
  turns into a red count (🔴 N) when N tracked repos have uncommitted changes.
- Click the pill to open the panel: it lists only the dirty repos with how
  many files changed in each.
- Pick a repo, type a commit message, hit **Push** — GitNotice runs
  `git add -A && git commit -m "…" && git push` for you.
- A collapsible "Manage repos" section lets you add new repo paths or remove
  ones you no longer want tracked.

## How it works

All the git plumbing lives in [`gitnotice.sh`](gitnotice.sh), a small bash +
jq helper invoked from QML via `Quickshell.Io.Process`. It keeps the tracked
repo list in `~/.config/gitnotice/repos.json` and always prints JSON, so the
QML side (`BarWidget.qml` / `Panel.qml`) never touches the filesystem or git
directly. Requires `bash`, `git`, and `jq` — all ship with Omarchy by default.

## Install

Copy (or symlink) this repo to:

```
~/.config/omarchy/plugins/sudhakar.gitnotice/
```

Then enable "GitNotice" from Omarchy's bar widget settings.
