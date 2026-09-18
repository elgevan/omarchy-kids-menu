import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "BarActions.js" as BarActions

// Preserve the normal Omarchy menu symbol in the stock menu's bar slot. This
// is an intentionally service-less inline entry under Omarchy 4.0.4's scoped
// plugin APIs, so it reads only this plugin's durable mode flag.
BarWidget {
  id: root
  moduleName: "io.github.elgevan.kids-menu.menu"

  property bool kidsModeEnabled: false
  readonly property string modePath: Quickshell.env("HOME")
    + "/.config/omarchy-kids/mode.json"

  function loadMode(rawText) {
    try {
      var value = JSON.parse(String(rawText || ""))
      root.kidsModeEnabled = value && value.version === 1 && value.enabled === true
    } catch (error) {
      root.kidsModeEnabled = false
    }
  }

  FileView {
    path: root.modePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadMode(text())
    onLoadFailed: root.kidsModeEnabled = false
    onFileChanged: reload()
  }

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
