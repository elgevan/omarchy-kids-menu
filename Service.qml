import QtQuick
import Quickshell
import Quickshell.Io
import "Allowlist.js" as Allowlist
import "NotificationState.js" as NotificationState

// Shared state for the menu and its bar-panel editor. The service reads
// DesktopEntries, writes plugin-owned state, and temporarily enables Omarchy's
// built-in Do Not Disturb mode while Kids Mode is active.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: ""
  property var allowedDesktopIds: Allowlist.defaultIds()
  property bool directoryReady: false
  property bool writePending: false
  property bool notificationStateLoaded: false
  property bool notificationStateManaged: false
  property bool notificationRestoreDnd: false
  property bool notificationApplied: false
  property int notificationSetupAttempts: 0

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy-kids"
  readonly property string configPath: configDir + "/allowed-apps.json"
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || homeDir + "/.local/state"
  readonly property string stateDir: stateRoot + "/omarchy-kids"
  readonly property string notificationStatePath: stateDir + "/notifications.json"
  readonly property var defaultDesktopIds: Allowlist.defaultIds()
  readonly property var notificationService: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("omarchy.notifications")
    : null
  readonly property bool notificationsMuted: root.notificationApplied
    && root.notificationService
    && root.notificationService.doNotDisturb === true
  readonly property string managerWidgetId: "omarchy-kids.manager"
  readonly property string managerWidgetPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/ManagerWidget.qml"
    : ""

  signal allowlistChanged()

  function sameIds(left, right) {
    var a = Allowlist.normalizeIds(left)
    var b = Allowlist.normalizeIds(right)
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }

  function replaceAllowedIds(values, persist) {
    var normalized = Allowlist.normalizeIds(values)
    var changed = !root.sameIds(root.allowedDesktopIds, normalized)
    root.allowedDesktopIds = normalized
    if (changed) root.allowlistChanged()
    if (persist) root.persist()
  }

  function load(rawText) {
    root.replaceAllowedIds(Allowlist.parseSettings(rawText), false)
  }

  function isAllowed(desktopId) {
    return Allowlist.contains(root.allowedDesktopIds, desktopId)
  }

  function isDefault(desktopId) {
    return Allowlist.contains(root.defaultDesktopIds, desktopId)
  }

  function setAllowed(desktopId, allowed) {
    var id = Allowlist.normalizeDesktopId(desktopId)
    if (!id) return

    var next = root.allowedDesktopIds.slice()
    var index = next.indexOf(id)
    if (allowed && index < 0) next.push(id)
    else if (!allowed && index >= 0) next.splice(index, 1)
    else return

    root.replaceAllowedIds(next, true)
  }

  function toggleAllowed(desktopId) {
    root.setAllowed(desktopId, !root.isAllowed(desktopId))
  }

  function resetDefaults() {
    root.replaceAllowedIds(root.defaultDesktopIds, true)
  }

  function persist() {
    root.writePending = true
    if (root.directoryReady) {
      root.flushWrite()
    } else if (!ensureDirectory.running) {
      ensureDirectory.running = true
    }
  }

  function flushWrite() {
    if (!root.writePending) return
    root.writePending = false
    settingsFile.setText(Allowlist.settingsText(root.allowedDesktopIds))
  }

  function loadNotificationState(rawText) {
    var state = NotificationState.parseState(rawText)
    root.notificationStateManaged = state.managed
    root.notificationRestoreDnd = state.restoreDnd
    root.notificationStateLoaded = true
    root.scheduleNotificationSetup()
  }

  function applyNotificationPolicy() {
    var notifications = root.notificationService
    if (!root.directoryReady || !root.notificationStateLoaded || !notifications
        || notifications.settingsLoaded !== true)
      return false

    if (!root.notificationStateManaged) {
      root.notificationRestoreDnd = notifications.doNotDisturb === true
      root.notificationStateManaged = true
      // Persist the restore point before changing the global DND state.
      notificationStateFile.setText(NotificationState.stateText(
        true, root.notificationRestoreDnd))
    }

    notifications.setDoNotDisturb(true)
    root.notificationApplied = true
    return true
  }

  function scheduleNotificationSetup() {
    root.notificationSetupAttempts = 0
    notificationSetup.restart()
  }

  function releaseNotificationPolicy() {
    if (!root.notificationStateLoaded || !root.notificationStateManaged) return
    var notifications = root.notificationService
    if (!notifications || notifications.settingsLoaded !== true) {
      console.warn("omarchy-kids: could not restore notification state")
      return
    }

    // Clear our ownership marker first. A future enable will then capture the
    // user's current DND preference as a fresh restore point.
    notificationStateFile.setText(NotificationState.stateText(false, false))
    root.notificationStateManaged = false
    root.notificationApplied = false
    notifications.setDoNotDisturb(root.notificationRestoreDnd)
  }

  function managerEntryMatches(entry) {
    return entry && String(entry.id || "") === root.managerWidgetId
      && String(entry.type || "") === "qml"
      && String(entry.source || "") === root.managerWidgetPath
  }

  function managerLocation(config) {
    var layout = config && config.bar ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    if (!layout) return null
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        if (entries[i] && String(entries[i].id || "") === root.managerWidgetId)
          return { section: sections[s], index: i, entry: entries[i] }
      }
    }
    return null
  }

  function ensureManagerWidget() {
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function" || !root.managerWidgetPath) return
    var existing = root.managerLocation(root.shell.shellConfig)
    if (existing && root.managerEntryMatches(existing.entry)) return

    root.shell.mutateShellConfig(function(config) {
      if (!config.bar) config.bar = ({})
      if (!config.bar.layout) config.bar.layout = ({})
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        if (!Array.isArray(config.bar.layout[sections[s]])) config.bar.layout[sections[s]] = []
      }

      var entry = { id: root.managerWidgetId, type: "qml", source: root.managerWidgetPath }
      var location = root.managerLocation(config)
      if (location) {
        config.bar.layout[location.section][location.index] = entry
        return
      }

      var right = config.bar.layout.right
      var insertAt = 0
      for (var i = 0; i < right.length; i++) {
        if (right[i] && String(right[i].id || right[i]) === "omarchy.tray") {
          insertAt = i + 1
          break
        }
      }
      right.splice(insertAt, 0, entry)
    })
  }

  function removeManagerWidget() {
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return
    if (!root.managerLocation(root.shell.shellConfig)) return
    root.shell.mutateShellConfig(function(config) {
      var layout = config && config.bar ? config.bar.layout : null
      if (!layout) return
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var entries = layout[sections[s]]
        if (!Array.isArray(entries)) continue
        layout[sections[s]] = entries.filter(function(entry) {
          return String((entry && entry.id) || entry || "") !== root.managerWidgetId
        })
      }
    })
  }

  FileView {
    id: settingsFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.load("")
    onFileChanged: reload()
  }

  FileView {
    id: notificationStateFile
    path: root.notificationStatePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadNotificationState(text())
    onLoadFailed: root.loadNotificationState("")
    onFileChanged: reload()
  }

  Process {
    id: ensureDirectory
    command: ["mkdir", "-p", root.configDir, root.stateDir]
    onExited: function(exitCode) {
      root.directoryReady = exitCode === 0
      if (root.directoryReady) {
        root.flushWrite()
        root.scheduleNotificationSetup()
      }
    }
  }

  Timer {
    id: notificationSetup
    interval: 100
    repeat: true
    onTriggered: {
      root.notificationSetupAttempts++
      if (root.applyNotificationPolicy()) {
        stop()
      } else if (root.notificationSetupAttempts >= 100) {
        console.warn("omarchy-kids: notification service was not ready")
        stop()
      }
    }
  }

  Timer {
    id: managerSetup
    interval: 0
    onTriggered: root.ensureManagerWidget()
  }

  onShellChanged: {
    managerSetup.restart()
    root.scheduleNotificationSetup()
  }
  onManifestChanged: managerSetup.restart()
  onNotificationServiceChanged: root.scheduleNotificationSetup()

  Component.onCompleted: {
    ensureDirectory.running = true
    managerSetup.restart()
    root.scheduleNotificationSetup()
  }

  Component.onDestruction: {
    if (root.pluginRegistry && !root.pluginRegistry.isEnabled("omarchy-kids.menu")) {
      root.releaseNotificationPolicy()
      root.removeManagerWidget()
    }
  }
}
