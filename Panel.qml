import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy-kids.manager"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property string filterText: ""
  property int installedAllowedCount: 0

  readonly property var barIdentity: hostWidget || root
  readonly property var appLibrary: bar && bar.shell ? bar.shell.appLibrary : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.rebuildApps()
    root.controller.show()
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function rebuildApps() {
    appModel.clear()
    root.installedAllowedCount = 0
    if (!root.appLibrary) return

    var installedRows = root.appLibrary.sortedEntries("")
    for (var available = 0; available < installedRows.length; available++) {
      var availableEntry = installedRows[available].entry
      if (root.service && availableEntry && root.service.isAllowed(availableEntry.id))
        root.installedAllowedCount++
    }

    var rows = root.appLibrary.sortedEntries(root.filterText)
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i].entry
      var id = String(entry.id || "")
      if (!id) continue
      appModel.append({
        appId: id,
        appName: root.appLibrary.entryName(entry),
        appDetail: root.appLibrary.entrySubtext(entry),
        appIcon: root.appLibrary.iconSource(String(entry.icon || "")),
        appAllowed: root.service ? root.service.isAllowed(id) : false
      })
    }
    if (appModel.count > 0 && appList.currentIndex < 0) appList.currentIndex = 0
  }

  function toggleCurrent() {
    if (!root.service || appList.currentIndex < 0 || appList.currentIndex >= appModel.count) return
    root.service.toggleAllowed(appModel.get(appList.currentIndex).appId)
  }

  ListModel { id: appModel }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.rebuildApps() }
  }

  Connections {
    target: root.service
    function onAllowlistChanged() { root.rebuildApps() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: searchInput
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(660))

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Column {
          width: parent.width - enabledPill.width - parent.spacing
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "KIDS MENU APPS"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 1.2
          }

          Text {
            width: parent.width
            text: "Choose which installed apps appear"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        BorderSurface {
          id: enabledPill
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: enabledText.implicitWidth + Style.space(14)
          implicitHeight: enabledText.implicitHeight + Style.space(7)
          radius: height / 2
          color: Style.selectedFillFor(root.accent, root.accent)
          borderSpec: Border.controlSpec("selected", root.accent, root.accent)

          Text {
            id: enabledText
            anchors.centerIn: parent
            text: root.installedAllowedCount + " SHOWN"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      BorderSurface {
        width: parent.width
        height: Style.space(42)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, root.accent)
        borderSpec: Border.controlSpec(searchInput.activeFocus ? "selected" : "normal", searchInput.activeFocus ? root.accent : root.foreground, root.accent)

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: searchInput.activeFocus ? root.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        TextInput {
          id: searchInput
          anchors.left: parent.left
          anchors.leftMargin: Style.space(38)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          selectionColor: root.accent
          selectedTextColor: Color.background
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          clip: true
          onTextChanged: {
            root.filterText = text
            root.rebuildApps()
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              if (appModel.count > 0) appList.currentIndex = Math.min(appModel.count - 1, appList.currentIndex + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              if (appModel.count > 0) appList.currentIndex = Math.max(0, appList.currentIndex - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              root.toggleCurrent()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              root.switchPanel((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
              event.accepted = true
            }
          }
        }

        Text {
          visible: searchInput.text.length === 0
          anchors.left: searchInput.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Search installed apps…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Item {
        width: parent.width
        height: Style.space(440)

        Text {
          visible: appModel.count === 0
          anchors.centerIn: parent
          text: root.appLibrary ? "No installed apps match" : "Loading installed apps…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        ListView {
          id: appList
          anchors.fill: parent
          model: appModel
          clip: true
          spacing: Style.space(4)
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: appModel.count > 0 ? 0 : -1

          delegate: BorderSurface {
            id: appRow
            required property int index
            required property string appId
            required property string appName
            required property string appDetail
            required property string appIcon
            required property bool appAllowed

            width: ListView.view.width
            height: Style.space(56)
            radius: Style.cornerRadius
            color: rowMouse.containsMouse || appList.currentIndex === appRow.index
              ? Style.hoverFillFor(root.accent, root.accent)
              : "transparent"
            borderSpec: appRow.appAllowed
              ? Border.controlSpec("selected", root.accent, root.accent)
              : Border.none()

            Image {
              id: iconImage
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(30)
              height: width
              source: appRow.appIcon
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              sourceSize.width: width
              sourceSize.height: height
            }

            Column {
              anchors.left: iconImage.right
              anchors.leftMargin: Style.space(10)
              anchors.right: stateText.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: appRow.appName
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: appRow.appAllowed
                elide: Text.ElideRight
              }

              Text {
                visible: text.length > 0
                width: parent.width
                text: appRow.appDetail
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Text {
              id: stateText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              text: appRow.appAllowed ? "✓" : "+"
              color: appRow.appAllowed ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                appList.currentIndex = appRow.index
                if (root.service) root.service.toggleAllowed(appRow.appId)
              }
            }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width - resetButton.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: "Only this menu changes; installed apps stay untouched."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        BorderSurface {
          id: resetButton
          implicitWidth: resetLabel.implicitWidth + Style.space(20)
          implicitHeight: resetLabel.implicitHeight + Style.space(10)
          radius: height / 2
          color: resetMouse.containsMouse
            ? Style.hoverFillFor(root.accent, root.accent)
            : Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

          Text {
            id: resetLabel
            anchors.centerIn: parent
            text: "RESET DEFAULTS"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MouseArea {
            id: resetMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.service) root.service.resetDefaults()
          }
        }
      }
    }
  }
}
