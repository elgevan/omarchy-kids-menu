import QtQuick
import qs.Commons
import qs.Ui
import "ServiceBridge.js" as ServiceBridge

// A separate, third-party-style control placed in the right bar section by
// Service.qml. The stock-looking left button remains dedicated to the menu.
BarWidget {
  id: root
  moduleName: "io.github.elgevan.kids-menu"

  property var allowlistService: null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property string modePhase: allowlistService
    ? String(allowlistService.modePhase || "inactive")
    : "inactive"
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false
  readonly property real openPanelIndicatorWidth: button.opticalSize

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.service = root.allowlistService
  }

  function resolveService() {
    var next = ServiceBridge.current()
    if (!next && root.bar && root.bar.shell
        && typeof root.bar.shell.serviceFor === "function")
      next = root.bar.shell.serviceFor("io.github.elgevan.kids-menu")
    if (root.allowlistService !== next) root.allowlistService = next
    serviceLookup.running = !next
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: {
    root.resolveService()
    root.injectPanel()
  }
  onSettingsChanged: injectPanel()
  onAllowlistServiceChanged: injectPanel()

  Timer {
    id: serviceLookup
    interval: 100
    repeat: true
    onTriggered: root.resolveService()
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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: Style.bar.statusSlot
    opticalSize: Style.bar.iconCanvas
    tooltipText: root.modePhase === "active"
      ? "Kids Menu: On"
      : root.modePhase === "entering"
        ? "Kids Menu: Starting…"
        : root.modePhase === "exiting" || root.modePhase === "rollback"
          ? "Kids Menu: Restoring…"
          : root.modePhase === "error"
            ? "Kids Menu: Needs attention"
            : "Kids Menu: Off"
    active: root.opened || root.modePhase === "active"
    onPressed: root.togglePanel()
  }

  Component.onCompleted: resolveService()
}
