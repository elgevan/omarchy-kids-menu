import QtQuick
import qs.Ui

// Preserve the normal Omarchy menu button and its usual left-hand position.
// The separate Kids manager widget is installed on the right by Service.qml.
BarWidget {
  id: root
  moduleName: "omarchy-kids.menu"

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
        root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"apps\"}'")
    }
  }
}
