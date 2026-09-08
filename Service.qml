import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  // ── Settings ────────────────────────────────────────────────────────
  property var settings: ({})

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)
  readonly property int warnPercent: intSetting("warnPercent", 80, 50, 99)
  readonly property int criticalPercent: intSetting("criticalPercent", 95, 75, 100)
  readonly property string showAccount: strSetting("showAccount", "worst")
  readonly property bool showCost: boolSetting("showCost", true)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function strSetting(name, fallback) {
    var v = String(setting(name, fallback))
    return v === "worst" ? "worst" : "none"
  }

  function boolSetting(name, fallback) {
    var v = setting(name, fallback)
    return v === true || v === "true"
  }

  // ── Data model (bounded) ────────────────────────────────────────────
  readonly property int maxAccounts: 8
  readonly property int maxWindows: 8
  readonly property int maxModels: 8

  // One entry per account: { id, label, kind, windows, cost, models }
  property var accounts: []

  // Aggregate bar state
  property int worstPercent: -1          // highest used-percent; -1 = no data
  property string worstLabel: ""
  property bool anyData: false
  property string lastError: ""
  property bool busy: false
  property string lastRefreshText: ""
  property bool credentialsReady: false

  readonly property bool alerting: worstPercent >= criticalPercent && worstPercent >= 0
  readonly property bool warning: !alerting && worstPercent >= warnPercent && worstPercent >= 0

  // ── Process deadlines ───────────────────────────────────────────────
  // Two layers, as in the approved ollama-status plugin:
  // `timeout -k 2 N` (primary, process-group aware) + QML watchdog (backup).
  readonly property int netTimeoutSec: 10
  readonly property int watchdogMs: 15000

  // ── Output caps at the OS pipe level ────────────────────────────────
  // `head -c N` bounds every producer; `set -o pipefail` turns SIGPIPE
  // truncation into exit 141, discarded by the exitCode === 0 guard.
  readonly property int capDiscovery: 2048
  readonly property int capUsage: 65536

  // ── Sanitize external strings for safe display ──────────────────────
  function sanitize(str) {
    return String(str || "").replace(/[<>&]/g, function(c) {
      if (c === "<") return "&lt;"
      if (c === ">") return "&gt;"
      if (c === "&") return "&amp;"
      return c
    })
  }

  function truncate(str, maxLen) {
    var s = String(str || "")
    if (s.length <= maxLen) return s
    return s.substring(0, maxLen) + "…"
  }

  function clampPercent(n) {
    var x = parseFloat(n)
    if (!isFinite(x)) x = 0
    if (x < 0) x = 0
    if (x > 100) x = 100
    return Math.round(x)
  }

  function authPath() {
    var home = Quickshell.env("HOME") || "/"
    return home + "/.local/share/opencode/auth.json"
  }

  // ── Refresh cycle ───────────────────────────────────────────────────
  // 1. discover: parse auth.json, emit one JSON line per account
  // 2. for each account: usage fetch (key piped over stdin, never argv)
  // 3. assemble when the outstanding-fetch latch hits zero

  function refresh() {
    if (busy) return
    busy = true
    lastError = ""
    launch(discoverProcess, discoverWatchdog)
  }

  function launch(process, watchdog) {
    if (!process.running) {
      process.running = true
      watchdog.restart()
    }
  }

  function reap(process, watchdog) {
    watchdog.stop()
    if (process.running) process.running = false
  }

  // discovery: read-only scan of the user's own auth store. The key list
  // is written to stdout as JSON lines; keys are then fed to curl via
  // stdin (-K -), so no key ever appears in a process argv or cmdline.
  readonly property string discoveryScript:
    "set -o pipefail; python3 - <<'PYEOF' 2>&1 | head -c " + capDiscovery + "\n" +
    "import json, os\n" +
    "path = os.path.join(os.path.expanduser('~'), '.local/share/opencode/auth.json')\n" +
    "try:\n" +
    "    with open(path) as f:\n" +
    "        d = json.load(f)\n" +
    "except Exception:\n" +
    "    pass\n" +
    "else:\n" +
    "    if isinstance(d, dict):\n" +
    "        for name, rec in d.items():\n" +
    "            if not isinstance(rec, dict):\n" +
    "                continue\n" +
    "            key = rec.get('key') or ''\n" +
    "            if not isinstance(key, str) or len(key) < 8:\n" +
    "                continue\n" +
    "            if name.startswith('opencode'):\n" +
    "                print(json.dumps({'id': name, 'kind': 'zen', 'label': name, 'key': key}))\n" +
    "            elif name == 'ollama-cloud':\n" +
    "                print(json.dumps({'id': name, 'kind': 'ollama', 'label': 'Ollama Cloud', 'key': key}))\n" +
    "PYEOF"

  // ── Discovery buffer ────────────────────────────────────────────────
  property string _discoverBuffer: ""
  readonly property int _discoverBufferMax: 2048

  function _onDiscoverLine(line) {
    var s = String(line || "")
    if (_discoverBuffer.length + s.length + 1 <= _discoverBufferMax) _discoverBuffer += s + "\n"
  }

  function _parseDiscoverBuffer() {
    var raw = truncate(_discoverBuffer.trim(), capDiscovery)
    _discoverBuffer = ""
    var found = []
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length && found.length < maxAccounts; i++) {
      var line = lines[i].trim()
      if (line.indexOf("{") !== 0) continue
      try {
        var rec = JSON.parse(line)
        if (rec && typeof rec.id === "string" && typeof rec.key === "string" &&
            (rec.kind === "zen" || rec.kind === "ollama")) {
          found.push({
            id: truncate(rec.id, 64),
            kind: rec.kind === "zen" ? "zen" : "ollama",
            label: truncate(rec.label || rec.id, 48),
            key: rec.key
          })
        }
      } catch (e) {
        // skip malformed lines
      }
    }
    credentialsReady = found.length > 0
    _resetFetchState(found)
    if (!credentialsReady) {
      accounts = []
      worstPercent = -1
      worstLabel = ""
      anyData = false
      busy = false
      lastRefreshText = ""
      lastError = "No AI accounts found.\nExpected keys in " + sanitize(authPath()) + "\n(opencode* or ollama-cloud). Run: opencode auth login"
      return
    }
    for (var j = 0; j < found.length; j++) {
      _fetchUsage(found[j])
    }
  }

  // ── Fetch latch ─────────────────────────────────────────────────────
  property var _pendingAccounts: []
  property var _results: []
  property var _errors: []
  property int _outstanding: 0

  property var _labelMap: ({})

  function _resetFetchState(found) {
    _pendingAccounts = found || []
    var map = {}
    for (var i = 0; i < _pendingAccounts.length; i++) {
      map[String(_pendingAccounts[i].id)] = _pendingAccounts[i].label
    }
    _labelMap = map
    _results = []
    _errors = []
    _outstanding = _pendingAccounts.length
  }

  function _finishAccount(accountId, windows, extra, ok, errMsg) {
    if (ok) {
      if (_results.length < maxAccounts) {
        _results.push({ id: accountId, windows: windows, extra: extra })
      }
    } else {
      if (_errors.length < maxAccounts) {
        _errors.push({ id: accountId, error: errMsg })
      }
    }
    _outstanding = _outstanding - 1
    if (_outstanding <= 0) _assemble()
  }

  // ── Parsers ─────────────────────────────────────────────────────────

  function _parseZen(accountId, raw) {
    var windows = []
    var d = JSON.parse(raw)
    var u = d && d.usage ? d.usage : {}
    var specs = [["rolling", "Rolling"], ["weekly", "Weekly"], ["monthly", "Monthly"]]
    for (var i = 0; i < specs.length && windows.length < maxWindows; i++) {
      var w = u[specs[i][0]]
      if (!w) continue
      windows.push({
        name: specs[i][1],
        percent: clampPercent(w.percent),
        resetInMs: _isoToMs(w.resetsAt),
        status: truncate(String(w.status || ""), 32)
      })
    }
    _finishAccount(accountId, windows, {}, true, "")
  }

  function _parseOllama(accountId, raw) {
    var windows = []
    var d = JSON.parse(raw)
    var lim = d && d.limits ? d.limits : {}
    var m = lim.monthly
    if (m && typeof m.usage !== "undefined") {
      windows.push({
        name: "Monthly",
        percent: clampPercent(parseFloat(m.usage) * 100),
        resetInMs: -1,
        status: "ok"
      })
    }
    var extra = {}
    if (d && d.activity) {
      if (typeof d.activity.cost !== "undefined") extra.cost = String(d.activity.cost)
      var models = []
      var arr = d.activity.models || []
      for (var i = 0; i < arr.length && i < maxModels; i++) {
        models.push({
          name: truncate(String(arr[i].name || ""), 48),
          requests: parseInt(arr[i].request_count, 10) || 0,
          cost: String(typeof arr[i].cost !== "undefined" ? arr[i].cost : "")
        })
      }
      extra.models = models
    }
    _finishAccount(accountId, windows, extra, true, "")
  }

  function _isoToMs(iso) {
    if (!iso) return -1
    var t = Date.parse(String(iso))
    return isFinite(t) ? t : -1
  }

  function _parseUsageBuffer(buffer, accountId, kind) {
    var raw = truncate(buffer.trim(), capUsage)
    if (raw === "") {
      _finishAccount(accountId, [], {}, false, "empty response")
      return
    }
    var firstBrace = raw.indexOf("{")
    if (firstBrace < 0) {
      _finishAccount(accountId, [], {}, false, truncate(raw, 80))
      return
    }
    if (firstBrace > 0) raw = raw.substring(firstBrace)
    try {
      if (kind === "zen") _parseZen(accountId, raw)
      else _parseOllama(accountId, raw)
    } catch (e) {
      _finishAccount(accountId, [], {}, false, truncate(String(e), 120))
    }
  }

  function _assemble() {
    var list = []
    var worst = -1
    var wLabel = ""
    for (var i = 0; i < _results.length && i < maxAccounts; i++) {
      var r = _results[i]
      var label = _labelMap[String(r.id)] || r.id
      var windows = []
      for (var k = 0; k < r.windows.length && k < maxWindows; k++) {
        var w = r.windows[k]
        windows.push({
          name: sanitize(truncate(w.name, 32)),
          percent: w.percent,
          resetInMs: w.resetInMs,
          status: sanitize(truncate(w.status, 24))
        })
        if (w.percent > worst) {
          worst = w.percent
          wLabel = label + " \u00b7 " + w.name
        }
      }
      var extra = r.extra || {}
      var safeModels = []
      var models = extra.models || []
      for (var m = 0; m < models.length && m < maxModels; m++) {
        safeModels.push({
          name: sanitize(truncate(models[m].name, 48)),
          requests: models[m].requests,
          cost: sanitize(truncate(models[m].cost, 16))
        })
      }
      list.push({
        id: sanitize(truncate(label, 48)),
        kind: r.id === "ollama-cloud" ? "ollama" : "zen",
        windows: windows,
        cost: sanitize(truncate(extra.cost || "", 16)),
        models: safeModels
      })
    }
    accounts = list
    worstPercent = worst
    worstLabel = wLabel
    anyData = list.length > 0
    busy = false
    lastRefreshText = Qt.formatDateTime(new Date(), "HH:mm")
    var msgs = []
    for (var e2 = 0; e2 < _errors.length; e2++) {
      msgs.push(sanitize(truncate(_errors[e2].id, 32)) + ": " + _errors[e2].error)
    }
    lastError = msgs.length > 0 ? truncate(msgs.join(" \u00b7 "), 200) : ""
    _resetFetchState([])
  }

  // ── Countdown formatting ────────────────────────────────────────────
  function formatReset(resetInMs) {
    if (!resetInMs || resetInMs < 0) return ""
    var diff = resetInMs - Date.now()
    if (diff <= 0) return "now"
    var mins = Math.floor(diff / 60000)
    if (mins < 60) return mins + "m"
    var hours = Math.floor(mins / 60)
    if (hours < 48) {
      var rem = mins % 60
      return rem > 0 ? (hours + "h " + rem + "m") : (hours + "h")
    }
    return Math.floor(hours / 24) + "d"
  }

  function formatCost(cost) {
    var s = String(cost || "")
    if (s === "") return ""
    var f = parseFloat(s)
    if (!isFinite(f)) return ""
    return "$" + f.toFixed(2)
  }

  // ── Processes ───────────────────────────────────────────────────────
  // API keys travel over stdin: bash reads exactly one line (read never
  // waits for EOF), parks it in a 0600 mktemp file under XDG_RUNTIME_DIR,
  // and hands that to `curl -H @file`. The file is removed by trap EXIT.
  // Nothing secret ever appears in argv or /proc/<pid>/cmdline, and the
  // key file exists for well under a second. curl must NOT read stdin
  // itself (-K - / -H @- block on the persistent plugin pipe), so bash
  // consumes the line and closes the loop.

  readonly property string curlBase:
    "set -o pipefail; IFS= read -r _hdr; " +
    "_f=$(mktemp \"${XDG_RUNTIME_DIR:-/tmp}/omadeck-hdr.XXXXXX\") || exit 1; " +
    "trap 'rm -f \"$_f\"' EXIT; " +
    "printf '%s\\n' \"$_hdr\" > \"$_f\"; chmod 600 \"$_f\"; " +
    "curl -sS -H @\"$_f\" --connect-timeout 5 --max-time 8 "

  Process {
    id: discoverProcess
    running: false
    command: ["timeout", "-k", "2", "" + root.netTimeoutSec,
              "bash", "-c", root.discoveryScript]
    stdout: SplitParser { onRead: function(line) { root._onDiscoverLine(line) } }
    onExited: function(exitCode) {
      discoverWatchdog.stop()
      if (exitCode === 0) root._parseDiscoverBuffer()
      else {
        root._discoverBuffer = ""
        root.busy = false
        root.lastError = "Account discovery failed (exit " + exitCode + "). Is python3 on PATH?"
      }
    }
  }

  Timer {
    id: discoverWatchdog
    interval: root.watchdogMs
    repeat: false
    onTriggered: root.reap(discoverProcess, discoverWatchdog)
  }

  // One static process slot per supported account. Keys are piped over
  // stdin on every start; the slot stays empty until discovery assigns it.
  Process {
    id: zenUsage1
    property string accountId: ""
    property string keyToWrite: ""
    stdinEnabled: true
    running: false
    command: ["timeout", "-k", "2", "" + root.netTimeoutSec,
              "bash", "-c", root.curlBase + "https://opencode.ai/zen/go/v1/usage 2>&1 | head -c " + root.capUsage]
    stdout: SplitParser { onRead: function(line) { root._onUsageLine(parent.accountId, line) } }
    onExited: function(exitCode) { root._onUsageExit(parent.accountId, "zen", exitCode) }
    onStarted: {
      write('Authorization: Bearer ' + keyToWrite + '\n')
      keyToWrite = ""
    }
  }

  Process {
    id: zenUsage2
    property string accountId: ""
    property string keyToWrite: ""
    stdinEnabled: true
    running: false
    command: ["timeout", "-k", "2", "" + root.netTimeoutSec,
              "bash", "-c", root.curlBase + "https://opencode.ai/zen/go/v1/usage 2>&1 | head -c " + root.capUsage]
    stdout: SplitParser { onRead: function(line) { root._onUsageLine(parent.accountId, line) } }
    onExited: function(exitCode) { root._onUsageExit(parent.accountId, "zen", exitCode) }
    onStarted: {
      write('Authorization: Bearer ' + keyToWrite + '\n')
      keyToWrite = ""
    }
  }

  Process {
    id: zenUsage3
    property string accountId: ""
    property string keyToWrite: ""
    stdinEnabled: true
    running: false
    command: ["timeout", "-k", "2", "" + root.netTimeoutSec,
              "bash", "-c", root.curlBase + "https://opencode.ai/zen/go/v1/usage 2>&1 | head -c " + root.capUsage]
    stdout: SplitParser { onRead: function(line) { root._onUsageLine(parent.accountId, line) } }
    onExited: function(exitCode) { root._onUsageExit(parent.accountId, "zen", exitCode) }
    onStarted: {
      write('Authorization: Bearer ' + keyToWrite + '\n')
      keyToWrite = ""
    }
  }

  Process {
    id: zenUsage4
    property string accountId: ""
    property string keyToWrite: ""
    stdinEnabled: true
    running: false
    command: ["timeout", "-k", "2", "" + root.netTimeoutSec,
              "bash", "-c", root.curlBase + "https://opencode.ai/zen/go/v1/usage 2>&1 | head -c " + root.capUsage]
    stdout: SplitParser { onRead: function(line) { root._onUsageLine(parent.accountId, line) } }
    onExited: function(exitCode) { root._onUsageExit(parent.accountId, "zen", exitCode) }
    onStarted: {
      write('Authorization: Bearer ' + keyToWrite + '\n')
      keyToWrite = ""
    }
  }

  Process {
    id: ollamaUsage
    property string accountId: ""
    property string keyToWrite: ""
    stdinEnabled: true
    running: false
    command: ["timeout", "-k", "2", "" + root.netTimeoutSec,
              "bash", "-c", root.curlBase + "https://ollama.com/api/usage 2>&1 | head -c " + root.capUsage]
    stdout: SplitParser { onRead: function(line) { root._onUsageLine(parent.accountId, line) } }
    onExited: function(exitCode) { root._onUsageExit(parent.accountId, "ollama", exitCode) }
    onStarted: {
      write('Authorization: Bearer ' + keyToWrite + '\n')
      keyToWrite = ""
    }
  }

  // ── Usage buffers, per slot ─────────────────────────────────────────
  property var _usageBuffers: ({})

  function _onUsageLine(accountId, line) {
    var s = String(line || "")
    var buf = String(_usageBuffers[accountId] || "")
    if (buf.length + s.length + 1 <= capUsage) _usageBuffers[accountId] = buf + s + "\n"
  }

  function _onUsageExit(accountId, kind, exitCode) {
    var buf = String(_usageBuffers[accountId] || "")
    _usageBuffers[accountId] = ""
    // Stale event from a slot reaped outside an active cycle: nothing to
    // finish, and a fresh cycle already owns the latch.
    if (String(accountId) === "" || _outstanding <= 0) return
    if (exitCode === 0) {
      _parseUsageBuffer(buf, accountId, kind)
    } else {
      _finishAccount(accountId, [], {}, false,
        exitCode === 124 || exitCode === 137 ? "timed out" :
        exitCode === 141 ? "response truncated" : "request failed (exit " + exitCode + ")")
    }
  }

  // ── Slot wiring ─────────────────────────────────────────────────────
  function _fetchUsage(account) {
    var proc = null
    if (account.kind === "zen") {
      if (String(account.id) === "opencode") proc = zenUsage1
      else if (String(account.id) === "opencode-go") proc = zenUsage2
      else if (String(account.id) === "opencode-go-2") proc = zenUsage3
      else proc = zenUsage4
    } else {
      proc = ollamaUsage
    }
    if (proc.running) {
      // slot busy (parallel refresh) — skip this cycle
      _finishAccount(account.id, [], {}, false, "slot busy")
      return
    }
    proc.accountId = account.id
    proc.keyToWrite = account.key
    launch(proc, account.kind === "zen" ? zenWatchdog : ollamaWatchdog)
  }

  Timer {
    id: zenWatchdog
    interval: root.watchdogMs
    repeat: false
    onTriggered: {
      root.reap(zenUsage1, zenWatchdog)
      root.reap(zenUsage2, zenWatchdog)
      root.reap(zenUsage3, zenWatchdog)
      root.reap(zenUsage4, zenWatchdog)
    }
  }

  Timer {
    id: ollamaWatchdog
    interval: root.watchdogMs
    repeat: false
    onTriggered: root.reap(ollamaUsage, ollamaWatchdog)
  }

  // ── Refresh timer ───────────────────────────────────────────────────
  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    refresh()
  }
}