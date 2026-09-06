import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.elgevan.kids-menu.manager"
  ipcTarget: "io.github.elgevan.kids-menu.manager"

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property string filterText: ""
  property bool showSelectedOnly: false
  property bool settingsOpen: false
  property int installedAllowedCount: 0
  property bool awaitingUnlock: false
  property string authError: ""

  readonly property int appGridColumnCount: 3

  readonly property var barIdentity: hostWidget || root
  readonly property var appLibrary: bar && bar.shell ? bar.shell.appLibrary : null
  readonly property var lockService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("omarchy.lock")
    : null
  readonly property bool allowlistEditable: root.service
    && root.service.allowlistEditable === true
  readonly property string modePhase: root.service
    ? String(root.service.modePhase || "inactive")
    : "inactive"
  readonly property bool modeActionEnabled: root.service && root.service.modeStateLoaded
    && (root.modePhase === "inactive" || root.modePhase === "active"
      || root.modePhase === "error")
    && (root.modePhase !== "inactive" || root.installedAllowedCount > 0)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.rebuildApps()
    root.controller.show()
    Qt.callLater(function() {
      if (root.settingsOpen) settingsBackButton.forceActiveFocus()
      else searchInput.forceActiveFocus()
    })
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() { root.controller.hide() }

  function showSettings(open) {
    root.settingsOpen = open === true
    Qt.callLater(function() {
      if (root.settingsOpen) settingsBackButton.forceActiveFocus()
      else searchInput.forceActiveFocus()
    })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function rebuildApps() {
    var currentAppId = ""
    if (appGrid.currentIndex >= 0 && appGrid.currentIndex < appModel.count)
      currentAppId = String(appModel.get(appGrid.currentIndex).appId || "")

    appModel.clear()
    root.installedAllowedCount = 0
    if (!root.appLibrary) return

    var installedRows = root.appLibrary.sortedEntries("")
    for (var available = 0; available < installedRows.length; available++) {
      var availableEntry = installedRows[available].entry
      if (!availableEntry || !String(availableEntry.id || "")) continue
      if (root.service && root.service.isAllowed(availableEntry.id))
        root.installedAllowedCount++
    }

    var rows = root.appLibrary.sortedEntries(root.filterText)
    var nextCurrentIndex = 0
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i].entry
      var id = String(entry.id || "")
      if (!id) continue
      var allowed = root.service ? root.service.isAllowed(id) : false
      if (root.showSelectedOnly && !allowed) continue
      if (id === currentAppId) nextCurrentIndex = appModel.count
      appModel.append({
        appId: id,
        appName: root.appLibrary.entryName(entry),
        appDetail: root.appLibrary.entrySubtext(entry),
        appIcon: root.appLibrary.iconSource(String(entry.icon || "")),
        appAllowed: allowed
      })
    }
    appGrid.currentIndex = appModel.count > 0 ? nextCurrentIndex : -1
    if (appGrid.currentIndex >= 0)
      appGrid.positionViewAtIndex(appGrid.currentIndex, GridView.Contain)
  }

  function emptyMessage() {
    if (!root.appLibrary) return "Loading installed apps…"
    if (root.showSelectedOnly && root.filterText.length > 0)
      return "No selected apps match this search"
    if (root.showSelectedOnly) return "No apps selected yet"
    if (root.filterText.length > 0) return "No apps match this search"
    return "No installed apps found"
  }

  function toggleCurrent() {
    if (!root.allowlistEditable || !root.service
        || appGrid.currentIndex < 0 || appGrid.currentIndex >= appModel.count) return
    root.service.toggleAllowed(appModel.get(appGrid.currentIndex).appId)
  }

  function selectedAppsLabel() {
    return root.installedAllowedCount + (root.installedAllowedCount === 1 ? " APP" : " APPS")
  }

  function toggleKidsMode() {
    if (!root.service || !root.modeActionEnabled) return
    root.authError = ""

    if (root.modePhase === "inactive") {
      root.service.setKidsModeEnabled(true)
      return
    }

    if (!root.lockService || typeof root.lockService.beginLock !== "function") {
      root.authError = "Authentication is unavailable"
      return
    }

    root.awaitingUnlock = true
    if (!root.lockService.beginLock()) {
      root.awaitingUnlock = false
      root.authError = "Could not start authentication"
      return
    }

    root.close()
  }

  function handleLockEvent() {
    if (!root.awaitingUnlock || !root.lockService) return
    if (String(root.lockService.lastEvent || "") === "unlocked") {
      root.awaitingUnlock = false
      if (root.service && !root.service.authorizeDeactivation())
        root.authError = "Could not restore the desktop"
    }
  }

  function modeStatusLabel() {
    if (root.modePhase === "entering") return "STARTING"
    if (root.modePhase === "active") return "ACTIVE"
    if (root.modePhase === "exiting" || root.modePhase === "rollback") return "RESTORING"
    if (root.modePhase === "error") return "ATTENTION"
    return "INACTIVE"
  }

  function modeActionLabel() {
    if (root.modePhase === "entering") return "PREPARING KIDS MENU…"
    if (root.modePhase === "exiting" || root.modePhase === "rollback")
      return "RESTORING DESKTOP…"
    if (root.modePhase === "error") return "AUTHENTICATE & RESTORE"
    if (root.modePhase === "active") return "EXIT KIDS MENU"
    return "START WITH " + root.selectedAppsLabel()
  }

  function modeActionDetail() {
    if (root.modePhase === "entering") return "Checking windows, shortcuts, shell, and notifications"
    if (root.modePhase === "exiting" || root.modePhase === "rollback")
      return "Kids Menu stays active until your desktop is restored"
    if (root.modePhase === "error")
      return "Kids Menu is still active; authenticate before restoring"
    if (root.modePhase === "active") {
      return root.service.hiddenWindowCount > 0
        ? "Use your password or fingerprint to restore " + root.service.hiddenWindowCount + " windows"
        : "Use your password or fingerprint to return to your desktop"
    }
    if (root.installedAllowedCount === 0) return "Choose at least one app to continue"
    return "Chosen apps, muted notifications, and protected web browsing"
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

  Connections {
    target: root.lockService
    function onLastEventChanged() { root.handleLockEvent() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: root.settingsOpen ? settingsBackButton : searchInput
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(root.settingsOpen
      ? settingsPage.implicitHeight : contentColumn.implicitHeight, Style.space(610))

    Column {
      id: contentColumn
      visible: !root.settingsOpen
      width: parent.width
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - headerActions.width - parent.spacing
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "KIDS MENU"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 1.2
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.authError.length > 0
              ? root.authError
              : root.service && root.service.modeTransitionError.length > 0
                ? root.service.modeTransitionError
              : root.service && root.service.windowSessionError.length > 0
                ? root.service.windowSessionError
                : root.service && root.service.shortcutPolicyError.length > 0
                  ? root.service.shortcutPolicyError
                  : root.service && root.service.browserProtectionError.length > 0
                    ? root.service.browserProtectionError
                  : root.modePhase === "active"
                    ? "Only the selected apps are available right now"
                    : "Choose the apps your child can use"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Row {
          id: headerActions
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          PanelActionButton {
            id: settingsButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒓"
            tooltipText: "Kids Menu settings"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.showSettings(true)
          }

          BorderSurface {
            id: modeStatus
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: modeStatusText.implicitWidth + Style.space(18)
            implicitHeight: modeStatusText.implicitHeight + Style.space(9)
            radius: height / 2
            color: root.modePhase === "active"
              ? Style.selectedFillFor(root.accent, root.accent)
              : Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec(
              root.modePhase === "active" ? "selected" : "normal",
              root.modePhase === "active" ? root.accent : root.foreground,
              root.accent
            )

            Text {
              id: modeStatusText
              anchors.centerIn: parent
              text: root.modeStatusLabel()
              color: root.modePhase === "active" ? root.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }
      }

      BorderSurface {
        id: modeAction
        width: parent.width
        height: Style.space(46)
        radius: Style.cornerRadius
        color: root.modePhase === "inactive"
          ? Style.selectedFillFor(root.accent, root.accent)
          : modeActionMouse.containsMouse
            ? Style.hoverFillFor(root.accent, root.accent)
            : Style.normalFillFor(root.foreground, root.accent)
        borderSpec: Border.controlSpec(
          root.modePhase === "inactive" ? "selected" : "normal",
          root.modePhase === "inactive" ? root.accent : root.foreground,
          root.accent
        )
        opacity: root.modeActionEnabled ? 1 : 0.55

        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.right: modeActionArrow.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            width: parent.width
            text: root.modeActionLabel()
            color: root.modePhase === "inactive" ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            width: parent.width
            text: root.modeActionDetail()
            color: root.modePhase === "inactive" ? root.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          id: modeActionArrow
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          text: "›"
          color: root.modePhase === "inactive" ? root.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        MouseArea {
          id: modeActionMouse
          anchors.fill: parent
          enabled: root.modeActionEnabled
          hoverEnabled: true
          cursorShape: root.modeActionEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.toggleKidsMode()
        }
      }

      BorderSurface {
        width: parent.width
        height: Style.space(38)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, root.accent)
        borderSpec: Border.controlSpec(searchInput.activeFocus ? "selected" : "normal", searchInput.activeFocus ? root.accent : root.foreground, root.accent)

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: searchInput.activeFocus ? root.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        TextInput {
          id: searchInput
          anchors.left: parent.left
          anchors.leftMargin: Style.space(34)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
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
            if ((event.modifiers & Qt.ControlModifier)
                && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_K) {
              root.toggleKidsMode()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              if (appGrid.currentIndex < 0 && appModel.count > 0) appGrid.currentIndex = 0
              appGrid.forceActiveFocus()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.toggleCurrent()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              if (event.modifiers & Qt.ShiftModifier) root.switchPanel(-1)
              else appGrid.forceActiveFocus()
              event.accepted = true
            }
          }
        }

        Text {
          visible: searchInput.text.length === 0
          anchors.left: searchInput.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Search apps…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Row {
        width: parent.width
        height: Style.space(32)
        spacing: Style.space(6)

        BorderSurface {
          width: (parent.width - parent.spacing) / 2
          height: parent.height
          radius: Style.cornerRadius
          color: !root.showSelectedOnly
            ? Style.selectedFillFor(root.accent, root.accent)
            : allAppsMouse.containsMouse
              ? Style.hoverFillFor(root.accent, root.accent)
              : Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec(
            !root.showSelectedOnly ? "selected" : "normal",
            !root.showSelectedOnly ? root.accent : root.foreground,
            root.accent
          )

          Text {
            anchors.centerIn: parent
            text: "ALL APPS"
            color: !root.showSelectedOnly ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MouseArea {
            id: allAppsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.showSelectedOnly = false
              root.rebuildApps()
            }
          }
        }

        BorderSurface {
          width: (parent.width - parent.spacing) / 2
          height: parent.height
          radius: Style.cornerRadius
          color: root.showSelectedOnly
            ? Style.selectedFillFor(root.accent, root.accent)
            : selectedAppsMouse.containsMouse
              ? Style.hoverFillFor(root.accent, root.accent)
              : Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec(
            root.showSelectedOnly ? "selected" : "normal",
            root.showSelectedOnly ? root.accent : root.foreground,
            root.accent
          )

          Text {
            anchors.centerIn: parent
            text: "SELECTED · " + root.installedAllowedCount
            color: root.showSelectedOnly ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MouseArea {
            id: selectedAppsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.showSelectedOnly = true
              root.rebuildApps()
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(360)

        Text {
          visible: appModel.count === 0
          anchors.centerIn: parent
          text: root.emptyMessage()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        GridView {
          id: appGrid
          anchors.fill: parent
          model: appModel
          clip: true
          cellWidth: width / root.appGridColumnCount
          cellHeight: Style.space(108)
          boundsBehavior: Flickable.StopAtBounds
          keyNavigationEnabled: true
          currentIndex: appModel.count > 0 ? 0 : -1

          Keys.onPressed: function(event) {
            if ((event.modifiers & Qt.ControlModifier)
                && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_K) {
              root.toggleKidsMode()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                       || event.key === Qt.Key_Space) {
              root.toggleCurrent()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
              if (event.modifiers & Qt.ShiftModifier) searchInput.forceActiveFocus()
              else root.switchPanel(1)
              event.accepted = true
            }
          }

          delegate: Item {
            id: tileCell
            required property int index
            required property string appId
            required property string appName
            required property string appDetail
            required property string appIcon
            required property bool appAllowed

            width: appGrid.cellWidth
            height: appGrid.cellHeight

            BorderSurface {
              id: appTile
              anchors.fill: parent
              anchors.rightMargin: Style.space(6)
              anchors.bottomMargin: Style.space(6)
              radius: Style.cornerRadius
              color: tileCell.appAllowed
                ? Style.selectedFillFor(root.accent, root.accent)
                : tileMouse.containsMouse || appGrid.currentIndex === tileCell.index
                  ? Style.hoverFillFor(root.accent, root.accent)
                  : Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec(
                tileCell.appAllowed ? "selected" : "normal",
                tileCell.appAllowed ? root.accent : root.foreground,
                root.accent
              )

              Image {
                id: iconImage
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(12)
                width: Style.space(38)
                height: width
                source: tileCell.appIcon
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: width
                sourceSize.height: height
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.top: iconImage.bottom
                anchors.topMargin: Style.space(6)
                textFormat: Text.PlainText
                text: tileCell.appName
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: tileCell.appAllowed
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }

              BorderSurface {
                visible: tileCell.appAllowed
                anchors.top: parent.top
                anchors.topMargin: Style.space(7)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(7)
                width: Style.space(20)
                height: width
                radius: height / 2
                color: root.accent
                borderSpec: Border.none()

                Text {
                  anchors.centerIn: parent
                  text: "✓"
                  color: Color.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              MouseArea {
                id: tileMouse
                anchors.fill: parent
                enabled: root.allowlistEditable
                hoverEnabled: true
                cursorShape: root.allowlistEditable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  appGrid.currentIndex = tileCell.index
                  if (root.service) root.service.toggleAllowed(tileCell.appId)
                }
              }
            }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          width: parent.width - resetButton.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: root.allowlistEditable ? "CLICK A TILE TO CHANGE" : "LOCKED WHILE ACTIVE"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        BorderSurface {
          id: resetButton
          implicitWidth: resetLabel.implicitWidth + Style.space(16)
          implicitHeight: resetLabel.implicitHeight + Style.space(8)
          radius: height / 2
          opacity: root.allowlistEditable ? 1 : 0.45
          color: resetMouse.containsMouse && root.allowlistEditable
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
            enabled: root.allowlistEditable
            hoverEnabled: true
            cursorShape: root.allowlistEditable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.service) root.service.resetDefaults()
          }
        }
      }
    }

    Column {
      id: settingsPage
      visible: root.settingsOpen
      width: parent.width
      spacing: Style.space(14)

      Item {
        width: parent.width
        implicitHeight: Math.max(settingsBackButton.implicitHeight,
          settingsLabels.implicitHeight)

        PanelActionButton {
          id: settingsBackButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰁍"
          tooltipText: "Back to apps"
          foreground: root.foreground
          focusable: true
          fontFamily: root.fontFamily
          onClicked: root.showSettings(false)
          Keys.onEscapePressed: function(event) {
            root.showSettings(false)
            event.accepted = true
          }
        }

        Column {
          id: settingsLabels
          anchors.left: settingsBackButton.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "SETTINGS"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            text: root.service && root.service.settingsEditable
              ? "Changes apply to the next Kids browser launch"
              : "Settings are locked while Kids Menu is active"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      PanelSeparator { foreground: root.foreground }

      Column {
        width: parent.width
        spacing: Style.space(7)

        Text {
          text: "WEB PROTECTION"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          width: parent.width
          text: "Choose one family-filtering DNS provider. No account is required."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.service ? root.service.browserProtectionOptions : []

          delegate: BorderSurface {
            id: providerOption
            required property var modelData
            readonly property bool selected: root.service
              && root.service.browserProtectionProvider === modelData.id
            width: settingsPage.width
            height: Math.max(Style.space(66),
              providerLabels.implicitHeight + Style.space(20))
            radius: Style.cornerRadius
            opacity: root.service && root.service.settingsEditable ? 1 : 0.55
            color: selected
              ? Style.selectedFillFor(root.accent, root.accent)
              : providerMouse.containsMouse
                ? Style.hoverFillFor(root.accent, root.accent)
                : Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec(
              selected ? "selected" : "normal",
              selected ? root.accent : root.foreground,
              root.accent
            )

            BorderSurface {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: width
              radius: height / 2
              color: providerOption.selected ? root.accent : "transparent"
              borderSpec: Border.controlSpec(
                providerOption.selected ? "selected" : "normal",
                providerOption.selected ? root.accent : root.foreground,
                root.accent
              )

              Text {
                visible: providerOption.selected
                anchors.centerIn: parent
                text: "✓"
                color: Color.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Column {
              id: providerLabels
              anchors.left: parent.left
              anchors.leftMargin: Style.space(44)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: providerOption.modelData.label
                color: providerOption.selected ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                width: parent.width
                text: providerOption.modelData.description
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            MouseArea {
              id: providerMouse
              anchors.fill: parent
              enabled: root.service && root.service.settingsEditable
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.service.setBrowserProtectionProvider(
                providerOption.modelData.id)
            }
          }
        }
      }

      PanelSeparator { foreground: root.foreground }

      Column {
        width: parent.width
        spacing: Style.space(7)

        Text {
          text: "KEEP PLUGINS AVAILABLE"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          width: parent.width
          text: "Selected user-installed widgets from the top-right bar stay usable in Kids Menu. Only choose plugins you trust a child to use."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: !root.service || root.service.exemptPluginOptions.length === 0
          width: parent.width
          text: "No user-installed widgets are in the top-right bar."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        ListView {
          id: pluginOptions
          visible: root.service && root.service.exemptPluginOptions.length > 0
          width: parent.width
          height: Style.space(170)
          model: root.service ? root.service.exemptPluginOptions : []
          spacing: Style.space(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          delegate: BorderSurface {
            id: pluginOption
            required property var modelData
            readonly property bool selected: root.service
              && root.service.isPluginExempt(modelData.id)
            width: pluginOptions.width
            height: Style.space(54)
            radius: Style.cornerRadius
            opacity: root.service && root.service.settingsEditable ? 1 : 0.55
            color: selected
              ? Style.selectedFillFor(root.accent, root.accent)
              : pluginMouse.containsMouse
                ? Style.hoverFillFor(root.accent, root.accent)
                : Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec(
              selected ? "selected" : "normal",
              selected ? root.accent : root.foreground,
              root.accent
            )

            BorderSurface {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: width
              radius: Style.space(4)
              color: pluginOption.selected ? root.accent : "transparent"
              borderSpec: Border.controlSpec(
                pluginOption.selected ? "selected" : "normal",
                pluginOption.selected ? root.accent : root.foreground,
                root.accent
              )

              Text {
                visible: pluginOption.selected
                anchors.centerIn: parent
                text: "✓"
                color: Color.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(44)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: pluginOption.modelData.label
                color: pluginOption.selected ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: pluginOption.modelData.id
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            MouseArea {
              id: pluginMouse
              anchors.fill: parent
              enabled: root.service && root.service.settingsEditable
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.service.togglePluginExempt(pluginOption.modelData.id)
            }
          }
        }
      }
    }
  }
}
