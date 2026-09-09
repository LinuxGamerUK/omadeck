import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "com.github.linuxgameruk.omadeck"
  ipcTarget: "com.github.linuxgameruk.omadeck"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)

  // Countdowns read this so a panel left open keeps telling the truth.
  property double nowMs: Date.now()

  property bool cursorActive: false

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    deck.refresh()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  Service {
    id: deck
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { deck.refresh(); return "ok" }
  }

  function pctColor(percent) {
    if (percent >= deck.criticalPercent) return root.urgent
    if (percent >= deck.warnPercent) return Color.accent
    return root.foreground
  }

  function windowLine(w) {
    var t = deck.formatReset(w.resetInMs)
    var s = w.percent + "% used"
    if (w.status === "rate-limited") s = "rate limited"
    return s + (t !== "" ? " \u00b7 resets in " + t : "")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) root.cursorActive = true
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(40), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: deck.refresh()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") deck.refresh() }
    }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        // ── Hero ────────────────────────────────────────────────────
        Item {
          width: parent.width
          implicitHeight: heroIcon.implicitHeight

          Text {
            id: heroIcon
            text: "\uf2c2"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: refreshButton.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "OmaDeck"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              textFormat: Text.PlainText
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: deck.busy ? "REFRESHING\u2026" : "AI USAGE DECK"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              textFormat: Text.PlainText
              elide: Text.ElideRight
            }
          }

          CursorSurface {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            implicitWidth: Math.max(refreshLabel.implicitWidth, Style.space(56))
            implicitHeight: Math.max(refreshLabel.implicitHeight, Style.space(28))

            Text {
              id: refreshLabel
              anchors.centerIn: parent
              text: deck.busy ? "\u2026" : "Refresh"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: deck.refresh()
            }
          }
        }

        // ── Error ───────────────────────────────────────────────────
        Text {
          visible: deck.lastError !== ""
          width: parent.width
          text: deck.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
        }

        // ── No accounts ─────────────────────────────────────────────
        CursorSurface {
          visible: !deck.credentialsReady
          width: parent.width
          implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
          foreground: root.foreground

          Text {
            id: missingText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(12)
            text: "No AI accounts found.\nOmaDeck reads provider keys from\n~/.local/share/opencode/auth.json\nSign in once with: opencode auth login"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
          }
        }

        // ── Account cards ───────────────────────────────────────────
        Repeater {
          model: deck.accounts

          Column {
            id: card
            required property int index
            required property var modelData
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator {
              visible: index > 0
              foreground: root.foreground
            }

            CursorSurface {
              width: parent.width
              foreground: root.foreground
              implicitHeight: cardHeader.implicitHeight + Style.spacing.rowPaddingX

              RowLayout {
                id: cardHeader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Text {
                  text: modelData.kind === "ollama" ? "\u2601" : "\uf2c2"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  textFormat: Text.PlainText
                  Layout.alignment: Qt.AlignVCenter
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.id
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                }

                Text {
                  visible: modelData.tier !== ""
                  text: modelData.tier
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                  Layout.alignment: Qt.AlignVCenter
                }

                Text {
                  visible: modelData.accountId !== "" && modelData.accountId !== modelData.id
                  text: modelData.accountId
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                  Layout.alignment: Qt.AlignVCenter
                }

                Text {
                  visible: modelData.kind === "ollama" && deck.showCost && modelData.cost !== ""
                  text: deck.formatCost(modelData.cost) + " spend"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                  Layout.alignment: Qt.AlignVCenter
                }
              }
            }

            // Windows with meters
            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: modelData.windows.length > 0

              Repeater {
                model: modelData.windows

                Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(3)

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                    }

                    Text {
                      text: root.windowLine(modelData)
                      color: root.pctColor(modelData.percent)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      textFormat: Text.PlainText
                      Layout.alignment: Qt.AlignVCenter
                    }
                  }

                  Meter {
                    width: parent.width
                    value: modelData.percent / 100.0
                    alarming: modelData.percent >= deck.criticalPercent
                  }
                }
              }
            }

            // No-window note
            Text {
              visible: modelData.windows.length === 0 && modelData.note === ""
              width: parent.width
              text: "No usage windows reported."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }

            // Auth/status note from the harness record (actionable, e.g.
            // "Run `claude auth login` to restore authoritative usage.")
            Text {
              visible: modelData.note !== ""
              width: parent.width
              text: modelData.note
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
            }

            // Prepaid balance meter (agent-usage balance ledger)
            Column {
              visible: modelData.balance !== null
              width: parent.width
              spacing: Style.space(3)

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  Layout.fillWidth: true
                  text: "Prepaid balance"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                }

                Text {
                  text: {
                    var b = modelData.balance
                    if (!b) return ""
                    var t = deck.formatCost(b.remaining) + " left of " + deck.formatCost(b.funded)
                    return t + (b.estimated ? " (est.)" : "")
                  }
                  color: {
                    var b = modelData.balance
                    if (!b || b.funded <= 0) return root.foreground
                    var usedFrac = 1 - (b.remaining / b.funded)
                    return usedFrac >= 0.9 ? root.urgent
                      : (usedFrac >= (root.deck.warnPercent / 100) ? Color.accent : root.foreground)
                  }
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                  Layout.alignment: Qt.AlignVCenter
                }
              }

              Meter {
                width: parent.width
                value: {
                  var b = modelData.balance
                  if (!b || b.funded <= 0) return 0
                  return (b.funded - b.remaining) / b.funded
                }
                alarming: {
                  var b = modelData.balance
                  if (!b || b.funded <= 0) return false
                  return (1 - (b.remaining / b.funded)) >= 0.9
                }
              }
            }

            // Ollama model breakdown
            Column {
              width: parent.width
              spacing: Style.space(4)
              visible: modelData.models.length > 0 && deck.showCost

              Text {
                width: parent.width
                text: "RECENT ACTIVITY (4 WEEKS)"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
                textFormat: Text.PlainText
              }

              Repeater {
                model: modelData.models

                CursorSurface {
                  required property var modelData
                  width: parent.width
                  foreground: root.foreground
                  implicitHeight: modelRow.implicitHeight + Style.spacing.rowPaddingX

                  RowLayout {
                    id: modelRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(8)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                    }

                    Text {
                      text: modelData.requests + " req" + (modelData.cost !== "" ? " \u00b7 " + deck.formatCost(modelData.cost) : "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      textFormat: Text.PlainText
                      Layout.alignment: Qt.AlignVCenter
                    }
                  }
                }
              }
            }
          }
        }

        // ── Footer ──────────────────────────────────────────────────
        Text {
          width: parent.width
          text: {
            if (deck.busy) return "Refreshing\u2026"
            if (deck.lastRefreshText === "") return ""
            return "Updated " + deck.lastRefreshText + " \u00b7 refresh every " + deck.refreshIntervalSec + "s \u00b7 R or right-click refreshes"
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  // Countdown ticker: keeps "resets in" honest while the panel is open.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Rounded track showing the share of the window used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }

  // Keep reset lines fresh even without data changes.
  Timer {
    interval: 60000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
}