# OmaDeck

**AI usage deck for the Omarchy bar** — live "percent used" meters and reset
countdowns for your AI provider accounts, ModelDeck-style, in a bar widget
and dropdown panel.

![OmaDeck panel](assets/screenshot.png)

OmaDeck merges two local sources — Omarchy's per-harness usage records
and the `opencode` credential store — and shows, per account, every
rate-limit window the provider reports:

- **OpenCode Zen accounts** (`opencode*` keys) — rolling, weekly, and
  monthly windows with exact reset times ("resets in 4h 59m", "rate
  limited · resets in 5d").
- **Ollama Cloud** — monthly usage percent, last-4-weeks spend, and a
  per-model request/cost breakdown.
- **Claude Code** — session + weekly windows and model-scoped caps.
- **Codex** — primary/secondary rate-limit windows and plan tier.
- **Fireworks** — prepaid balance (funded vs spent).

The **bar** shows the deck glyph plus the worst window's percentage,
colour-coded: plain when healthy, accent at your warn threshold, red at
critical. The **panel** (left-click) lists one card per account with
meters and countdowns. Right-click forces a refresh.

## Install

```sh
omarchy plugin add https://github.com/LinuxGamerUK/omadeck.git --enable
```

Then place it where you like:

```sh
omarchy bar move com.github.linuxgameruk.omadeck --section right
```

## Remove

```sh
omarchy plugin remove com.github.linuxgameruk.omadeck
```

## Requirements

- Omarchy Quattro (quickshell shell) — tested against Quattro's plugin
  contract (`schemaVersion: 1`).
- **Python 3** and **curl** — both ship with Arch/Omarchy; no extra
  packages, no AUR builds, nothing downloaded at runtime.
- At least one signed-in provider account (see below).

## Harness coverage (provider-agnostic by design)

OmaDeck hardcodes **no subscriptions**. It merges two local, user-scope
sources on every refresh:

**1. Omarchy's own agent-usage records** — `~/.local/state/omarchy/agents/usage/`.
Omarchy ships one collector per AI harness (`omarchy-agent-usage-*`);
OmaDeck runs the official `omarchy-agent-usage-update --limits-only`
tool (user-scope, no privileges, the same tool the built-in Agents panel
uses) and reads the display-ready JSON records it writes:

| Harness | Covered via | Limits shown |
|---|---|---|
| **Claude Code** | Anthropic OAuth usage endpoint | 5-hour session + 7-day weekly windows, model-scoped caps |
| **Codex** | Codex app-server RPC | primary + secondary rate-limit windows, plan tier |
| **Fireworks** | Fireworks billing / funded-credit estimate | prepaid balance meter (funded vs spent) |
| **any future collector** | the same record contract | automatic — OmaDeck shows whatever records appear |

Unauthenticated harnesses show a card with the harness's own actionable
sign-in instruction (e.g. "Run `claude auth login`…") instead of meters,
so new users see exactly what to do next.

**2. OmaDeck's own credential scan** — `~/.local/share/opencode/auth.json`
(the store `opencode auth login` maintains), which covers the
subscriptions Omarchy's collectors don't:

| Provider | Covered via | Limits shown |
|---|---|---|
| **OpenCode Zen** (any `opencode*` account: Zen, Go, Go 2, future plans) | `auth.json` key | rolling / weekly / monthly windows with reset times |
| **Ollama Cloud** | `auth.json` key (`ollama-cloud`) | monthly usage %, 4-week spend, per-model request/cost |

Accounts you sign into appear on the next refresh with zero
configuration; subscriptions you don't hold simply don't appear —
detection is a scan of keys you actually hold, not a probe of provider
catalogs.

**Launcher-style harnesses without usage APIs** — Omarchy also ships
agents like Pi, Oh My Pi, Ori, Crush, Grok CLI, OpenClaw, Antigravity,
Hermes, GitHub Copilot, Cursor CLI, and Muse Code. Most of these are
launchers over providers (or their vendors expose no rate-limit API a
local key can query), so there is nothing usage-shaped to scan today.
When any of them gains an Omarchy collector — or an official usage
endpoint reachable with the credentials the CLI already holds — OmaDeck
picks it up automatically through source 1 or the `auth.json` scan,
with no OmaDeck update needed.

## Usage

| Action | Result |
|---|---|
| Left-click | Toggle the usage deck panel |
| Right-click | Refresh now |
| `R` in panel | Refresh now |
| Esc | Close panel |

Scriptable IPC:

```sh
omarchy-shell com.github.linuxgameruk.omadeck toggle
omarchy-shell com.github.linuxgameruk.omadeck open
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
| Show Ollama spend | on | Ollama cost + model activity cards |

## Privacy & security

- **Local-first.** The only network traffic is HTTPS GET to
  `https://opencode.ai/zen/go/v1/usage` and `https://ollama.com/api/usage`
  — the providers whose keys you already hold. No other hosts, no
  telemetry, no update checks, no downloads.
- **Keys never appear in process arguments.** Account discovery reads
  `auth.json` locally; each key is then piped to `curl` **over stdin**,
  where bash parks it in a `0600` temp file under `$XDG_RUNTIME_DIR`
  that is deleted on exit (`trap`), well under a second later. No key is
  ever in argv, `/proc/*/cmdline`, or any repo file.
- **No privileged operations.** No `sudo`, no `pkexec`, no system
  services, no config files written anywhere. The plugin runs entirely
  as your user. The one external command it runs is Omarchy's own
  `omarchy-agent-usage-update` — the same user-scope collector the
  built-in Agents panel uses.
- **No runtime code execution from outside.** Nothing is cloned, built,
  fetched, or executed beyond the two hardcoded API GETs and the local
  discovery script.
- **Bounded I/O everywhere.** Every subprocess runs under
  `timeout -k 2 N` (process-group kill) plus a QML watchdog fallback;
  every output stream is capped at the OS pipe level
  (`set -o pipefail; … | head -c N`) before parsing; parsed collections
  (accounts, windows, model rows, buffers) have fixed caps; output is
  parsed only on `exitCode === 0`; every string from an external source
  is sanitized (`<>&`) and rendered with `Text.PlainText`.
- **Failures are actionable.** Missing keys, timeouts, truncations, and
  per-account errors are surfaced by name in the panel instead of a bare
  "failed".

## Dependencies

- `python3` (discovery; base Arch install)
- `curl` (API polling; base Arch install)
- `omarchy-agent-usage-update` (ships with Omarchy; covers Claude Code,
  Codex, Fireworks, and future collectors)
- Omarchy Quattro shell with Quickshell

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

Inspired by [ModelDeck](https://github.com/timharris707/modeldeck)
(macOS menu-bar usage deck). OmaDeck is an independent implementation
for Omarchy/Quickshell — no code shared.