import QtQuick
import qs.Commons
import qs.Ui

// A separate, third-party-style control placed in the right bar section by
// Service.qml. The stock-looking left button remains dedicated to the menu.
BarWidget {
  id: root
  moduleName: "io.github.elgevan.omarchy-kids.manager"

  readonly property var allowlistService: bar && bar.shell
    ? bar.shell.serviceFor("io.github.elgevan.omarchy-kids")
    : null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool kidsModeEnabled: allowlistService
    ? allowlistService.kidsModeEnabled !== false
    : true
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

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onAllowlistServiceChanged: injectPanel()

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
    tooltipText: root.kidsModeEnabled ? "Kids Mode: On" : "Kids Mode: Off"
    active: root.opened || root.kidsModeEnabled
    onPressed: root.togglePanel()
  }
}
