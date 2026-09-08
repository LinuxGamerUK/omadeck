import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "com.github.linuxgameruk.omadeck"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Shape contract for shell.summon/hide/toggle routing
  // (Bar.findPanelWidget requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function refresh() {
    deck.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Service {
    id: deck
    settings: root.settings
  }

  readonly property color barIconColor: {
    if (!deck.credentialsReady)
      return bar ? Qt.darker(bar.barForeground, 2.0) : Qt.darker(Color.foreground, 2.0)
    if (deck.alerting) return bar ? bar.urgent : Color.urgent
    if (deck.warning) return Color.accent
    return bar ? bar.barForeground : Color.foreground
  }

  readonly property string barText: {
    if (!deck.credentialsReady || !deck.anyData || deck.busy) return ""
    if (deck.showAccount !== "worst") return ""
    return deck.worstPercent + "%"
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText !== "" ? ("\uf2c2 " + root.barText) : "\uf2c2"
    fontSize: root.barText !== "" ? Style.font.bodySmall : Style.bar.iconFont
    horizontalMargin: root.barText !== "" ? 8.5 : 0
    tooltipText: {
      if (!deck.credentialsReady) return "OmaDeck \u00b7 No accounts found"
      if (deck.busy) return "OmaDeck \u00b7 Refreshing\u2026"
      if (!deck.anyData) return "OmaDeck \u00b7 No usage data"
      return "OmaDeck \u00b7 " + deck.worstLabel + " \u00b7 " + deck.worstPercent + "% used"
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) deck.refresh()
    }
  }
}