# OmaDeck

**AI usage deck for the Omarchy bar** — live "percent used" meters and reset
countdowns for your AI provider accounts, ModelDeck-style, in a bar widget
and dropdown panel.

![OmaDeck panel](assets/screenshot.png)

OmaDeck watches the provider accounts you have already signed into with
[opencode](https://opencode.ai) — OpenCode Zen accounts (`opencode*` keys)
and Ollama Cloud — and shows, per account, every rate-limit window it
reports: rolling/weekly/monthly for Zen, monthly usage + 4-week spend and
per-model request/cost breakdown for Ollama Cloud.

- **Bar:** deck glyph, worst-window percentage beside it, colour-coded —
  plain when healthy, accent at your warn threshold, red at critical.
- **Panel (click):** one card per account with meters, reset countdowns
  ("resets in 4h 59m"), Ollama spend and per-model activity.
- **Right-click:** force a refresh.

## Install

```sh
omarchy plugin add https://github.com/LinuxGamerUK/omadeck.git --enable
```

Then move it where you like:

```sh
omarchy bar move com.github.linuxgameruk.omadeck --section right
```

## Requirements

- Omarchy Quattro (quickshell shell).
- **Python 3** (account discovery) and **curl** — both ship with Arch.
- At least one signed-in provider account. OmaDeck reads keys **only**
  from `~/.local/share/opencode/auth.json`, which `opencode auth login`
  creates:

  ```sh
  opencode auth login   # pick OpenCode Zen or Ollama Cloud
  ```

  No supported account found → the widget dims and the panel explains what
  to do. No other files, keyrings, or stores are ever read.

## Usage

| Action | Result |
|---|---|
| Left-click | Toggle the usage deck panel |
| Right-click | Refresh now |
| `R` in panel | Refresh now |
| Esc | Close panel |

IPC (scriptable):

```sh
omarchy-shell com.github.linuxgameruk.omadeck toggle
omarchy-shell com.github.linuxgameruk.omadeck refresh
```

## Settings

Configured from Omarchy's bar settings (widget settings form):

| Setting | Default | Meaning |
|---|---|---|
| Refresh interval (s) | 300 | Poll cadence, 60–3600 |
| Warn threshold (%) | 80 | Bar text turns accent at/above |
| Critical threshold (%) | 95 | Bar turns red at/above |
| Bar shows | `worst` | `worst` = worst window %, `none` = glyph only |
| Show Ollama spend | on | Ollama cost + model activity in the deck |

## Privacy & security

- **Local-first.** The only network calls are HTTPS GETs to
  `https://opencode.ai/zen/go/v1/usage` and `https://ollama.com/api/usage`
  — the providers you already use, with the keys you already stored.
- **Keys are never exposed.** Keys are read from `auth.json` by a local
  discovery step and passed to curl **over stdin**, then parked in a
  0600 temp file for under a second. No key ever appears in a process
  argv, `/proc/*/cmdline`, or the repo.
- **No telemetry, no downloads.** The plugin never downloads or executes
  third-party code and never writes outside its own temp header files.
- **No privileges.** No sudo/pkexec, no system services — everything runs
  as your user, all subprocesses are `timeout`-wrapped with output capped
  at the OS pipe level.

## Remove

```sh
omarchy plugin remove com.github.linuxgameruk.omadeck
```

## License

MIT — see [LICENSE](LICENSE).