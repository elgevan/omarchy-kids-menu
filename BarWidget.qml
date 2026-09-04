import QtQuick
import qs.Ui
import "BarActions.js" as BarActions

// Preserve the normal Omarchy menu symbol while using this plugin's own
// permanent ID. Service.qml moves this widget into the stock menu's bar slot.
BarWidget {
  id: root
  moduleName: "io.github.elgevan.kids-mode"

  readonly property var allowlistService: root.bar && root.bar.shell
    && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor("io.github.elgevan.kids-mode")
    : null
  readonly property bool kidsModeEnabled: root.allowlistService
    ? root.allowlistService.kidsModeEnabled === true
    : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\ue900"
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    tooltipText: "Omarchy menu"
    onPressed: function(buttonCode) {
      if (!root.bar) return
      const command = BarActions.commandFor(
        root.kidsModeEnabled,
        buttonCode === Qt.RightButton
      )
      if (command.length > 0) root.bar.run(command)
    }
  }
}
