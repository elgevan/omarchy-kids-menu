import QtQuick
import qs.Ui

// Preserve the normal Omarchy menu symbol while using this plugin's own
// permanent ID. Service.qml moves this widget into the stock menu's bar slot.
BarWidget {
  id: root
  moduleName: "io.github.elgevan.omarchy-kids"

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
      if (buttonCode === Qt.LeftButton && root.bar)
        root.bar.run("omarchy-shell shell toggle io.github.elgevan.omarchy-kids '{\"menu\":\"apps\"}'")
    }
  }
}
