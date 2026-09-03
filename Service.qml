import QtQuick
import Quickshell
import Quickshell.Io
import "Allowlist.js" as Allowlist
import "ModeState.js" as ModeState
import "NotificationState.js" as NotificationState
import "ShellIntegration.js" as ShellIntegration

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
  property bool kidsModeEnabled: true
  property bool modeStateLoaded: false
  property bool modeWritePending: false
  property bool notificationStateLoaded: false
  property bool notificationStateManaged: false
  property bool notificationRestoreDnd: false
  property bool notificationApplied: false
  property int notificationSetupAttempts: 0
  property int hiddenWindowCount: 0
  property bool windowSessionBusy: false
  property string windowSessionError: ""
  property bool windowSessionDesired: true
  property int windowGuardAttemptsRemaining: 0
  property var stockMenuRestore: null
  property bool shellIntegrationReady: false
  property bool shortcutPolicyApplied: false
  property bool shortcutPolicyBusy: false
  property string shortcutPolicyError: ""
  property string shortcutPolicyDesiredSignature: ""
  property string shortcutPolicyRunningSignature: ""

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy-kids"
  readonly property string configPath: configDir + "/allowed-apps.json"
  readonly property string modePath: configDir + "/mode.json"
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
  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id)
    : "io.github.elgevan.omarchy-kids"
  readonly property string managerWidgetId: pluginId + ".manager"
  readonly property string managerWidgetPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/ManagerWidget.qml"
    : ""
  readonly property string windowSessionTool: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/window-session"
    : ""
  readonly property string shortcutPolicyTool: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/shortcut-policy"
    : ""

  signal allowlistChanged()
  signal kidsModeChanged()

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
    if (changed) {
      root.allowlistChanged()
      root.scheduleShortcutPolicySync()
    }
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

  function loadModeState(rawText) {
    var enabled = ModeState.parseEnabled(rawText)
    var changed = root.kidsModeEnabled !== enabled
    root.kidsModeEnabled = enabled
    root.modeStateLoaded = true
    if (changed) root.kidsModeChanged()
    root.scheduleNotificationSetup()
    root.scheduleWindowSessionSync()
    root.scheduleShellIntegration()
    root.scheduleShortcutPolicySync()
  }

  function setKidsModeEnabled(enabled) {
    var next = enabled !== false
    if (!root.modeStateLoaded || root.kidsModeEnabled === next) return
    root.kidsModeEnabled = next
    root.kidsModeChanged()
    root.persistModeState()
    root.scheduleNotificationSetup()
    root.scheduleWindowSessionSync()
    root.scheduleShellIntegration()
    root.scheduleShortcutPolicySync()
  }

  function persistModeState() {
    root.modeWritePending = true
    if (root.directoryReady) {
      root.flushModeWrite()
    } else if (!ensureDirectory.running) {
      ensureDirectory.running = true
    }
  }

  function flushModeWrite() {
    if (!root.modeWritePending) return
    root.modeWritePending = false
    modeStateFile.setText(ModeState.stateText(root.kidsModeEnabled))
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
    if (!root.kidsModeEnabled || !root.directoryReady || !root.notificationStateLoaded || !notifications
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
    if (!root.notificationStateLoaded || !root.notificationStateManaged) {
      root.notificationApplied = false
      return true
    }
    var notifications = root.notificationService
    if (!notifications || notifications.settingsLoaded !== true) {
      console.warn("omarchy-kids: could not restore notification state")
      return false
    }

    // Clear our ownership marker first. A future enable will then capture the
    // user's current DND preference as a fresh restore point.
    notificationStateFile.setText(NotificationState.stateText(false, false))
    root.notificationStateManaged = false
    root.notificationApplied = false
    notifications.setDoNotDisturb(root.notificationRestoreDnd)
    return true
  }

  function syncModeEffects() {
    if (!root.modeStateLoaded || !root.notificationStateLoaded || !root.directoryReady)
      return false
    return root.kidsModeEnabled
      ? root.applyNotificationPolicy()
      : root.releaseNotificationPolicy()
  }

  function parseWindowSessionOutput(rawText) {
    try {
      var parsed = JSON.parse(String(rawText || "").trim())
      return parsed && typeof parsed === "object" ? parsed : null
    } catch (error) {
      return null
    }
  }

  function scheduleWindowSessionSync() {
    if (!root.modeStateLoaded || !root.windowSessionTool) return
    root.windowSessionDesired = root.kidsModeEnabled
    windowSessionSync.restart()
  }

  function syncWindowSession() {
    if (!root.modeStateLoaded || !root.windowSessionTool
        || windowSessionEnter.running || windowSessionExit.running)
      return

    root.windowSessionBusy = true
    root.windowSessionError = ""
    if (root.windowSessionDesired) windowSessionEnter.running = true
    else windowSessionExit.running = true
  }

  function finishWindowSession(action, exitCode, output) {
    var result = root.parseWindowSessionOutput(output)
    root.windowSessionBusy = false

    if (exitCode !== 0 || !result) {
      root.windowSessionError = action === "enter"
        ? "Could not hide existing windows"
        : "Could not restore hidden windows"
    } else if (action === "enter") {
      root.hiddenWindowCount = Math.max(0, Number(result.hidden || 0))
    } else {
      root.hiddenWindowCount = 0
    }

    if ((action === "enter") !== root.windowSessionDesired)
      windowSessionSync.restart()
  }

  function guardAppLaunch() {
    if (!root.kidsModeEnabled || !root.windowSessionTool) return
    root.windowGuardAttemptsRemaining = 2
    windowGuardTimer.interval = 650
    windowGuardTimer.restart()
  }

  function shortcutAllowed(ids) {
    for (var i = 0; i < ids.length; i++) {
      if (root.isAllowed(ids[i])) return true
    }
    return false
  }

  function shortcutPolicySignature() {
    if (!root.kidsModeEnabled) return "off"
    return "on:"
      + (root.shortcutAllowed(["chromium", "google-chrome", "google-chrome-stable"]) ? "1" : "0")
      + (root.isAllowed("omawrite") ? "1" : "0")
      + (root.isAllowed("omacalc") ? "1" : "0")
  }

  function scheduleShortcutPolicySync() {
    if (!root.modeStateLoaded || !root.shortcutPolicyTool) return
    root.shortcutPolicyDesiredSignature = root.shortcutPolicySignature()
    shortcutPolicySync.restart()
  }

  function syncShortcutPolicy() {
    if (!root.modeStateLoaded || !root.shortcutPolicyTool || root.shortcutPolicyBusy)
      return

    root.shortcutPolicyBusy = true
    root.shortcutPolicyError = ""
    root.shortcutPolicyRunningSignature = root.shortcutPolicyDesiredSignature

    if (root.shortcutPolicyRunningSignature === "off") {
      shortcutPolicyExit.running = true
      return
    }

    var signature = root.shortcutPolicyRunningSignature
    shortcutPolicyEnter.command = [
      root.shortcutPolicyTool,
      "enter",
      signature.charAt(3) === "1" ? "true" : "false",
      signature.charAt(4) === "1" ? "true" : "false",
      signature.charAt(5) === "1" ? "true" : "false"
    ]
    shortcutPolicyEnter.running = true
  }

  function finishShortcutPolicy(action, exitCode, output) {
    var result = root.parseWindowSessionOutput(output)
    root.shortcutPolicyBusy = false

    if (exitCode !== 0 || !result) {
      root.shortcutPolicyError = action === "enter"
        ? "Could not filter keyboard shortcuts"
        : "Could not restore keyboard shortcuts"
      root.shortcutPolicyApplied = action === "exit"
    } else {
      root.shortcutPolicyApplied = action === "enter" && result.applied === true
      if (result.error) root.shortcutPolicyError = String(result.error)
    }

    if (root.shortcutPolicyRunningSignature !== root.shortcutPolicyDesiredSignature)
      shortcutPolicySync.restart()
  }

  function scheduleShellIntegration() {
    shellIntegrationSetup.restart()
  }

  function syncShellIntegration() {
    if (!root.modeStateLoaded || !root.shell
        || typeof root.shell.mutateShellConfig !== "function"
        || !root.managerWidgetPath || !root.pluginId)
      return

    // The stock menu is deliberately unavailable while Kids Mode is active:
    // without clonedFrom, its IPC route cannot be redirected safely.
    if (root.kidsModeEnabled && typeof root.shell.hide === "function")
      root.shell.hide(ShellIntegration.STOCK_MENU_ID)

    root.shell.mutateShellConfig(function(config) {
      var result = ShellIntegration.activate(
        config,
        root.pluginId,
        root.managerWidgetId,
        root.managerWidgetPath,
        root.kidsModeEnabled
      )
      if (result && result.restore) root.stockMenuRestore = result.restore
    })
    root.shellIntegrationReady = true
  }

  function releaseShellIntegration() {
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return
    root.shell.mutateShellConfig(function(config) {
      ShellIntegration.deactivate(config, root.managerWidgetId, root.stockMenuRestore)
    })
    root.shellIntegrationReady = false
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
    id: modeStateFile
    path: root.modePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadModeState(text())
    onLoadFailed: root.loadModeState("")
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
        root.flushModeWrite()
        root.scheduleNotificationSetup()
      }
    }
  }

  Process {
    id: windowSessionEnter
    command: root.windowSessionTool ? [root.windowSessionTool, "enter"] : []
    stdout: StdioCollector { id: windowSessionEnterOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishWindowSession("enter", exitCode, windowSessionEnterOutput.text)
    }
  }

  Process {
    id: windowSessionExit
    command: root.windowSessionTool ? [root.windowSessionTool, "exit"] : []
    stdout: StdioCollector { id: windowSessionExitOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishWindowSession("exit", exitCode, windowSessionExitOutput.text)
    }
  }

  Process {
    id: windowSessionGuard
    command: root.windowSessionTool ? [root.windowSessionTool, "guard"] : []
    stdout: StdioCollector { id: windowSessionGuardOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var result = root.parseWindowSessionOutput(windowSessionGuardOutput.text)
      if (exitCode === 0 && result && Number(result.blocked || 0) > 0) {
        Quickshell.execDetached([
          "omarchy-notification-send",
          "That app is already open outside Kids Mode and remains hidden."
        ])
      }

      root.windowGuardAttemptsRemaining--
      if (root.windowGuardAttemptsRemaining > 0 && root.kidsModeEnabled) {
        windowGuardTimer.interval = 1200
        windowGuardTimer.restart()
      }
    }
  }

  Process {
    id: shortcutPolicyEnter
    command: []
    stdout: StdioCollector { id: shortcutPolicyEnterOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishShortcutPolicy("enter", exitCode, shortcutPolicyEnterOutput.text)
    }
  }

  Process {
    id: shortcutPolicyExit
    command: root.shortcutPolicyTool ? [root.shortcutPolicyTool, "exit"] : []
    stdout: StdioCollector { id: shortcutPolicyExitOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishShortcutPolicy("exit", exitCode, shortcutPolicyExitOutput.text)
    }
  }

  Timer {
    id: notificationSetup
    interval: 100
    repeat: true
    onTriggered: {
      root.notificationSetupAttempts++
      if (root.syncModeEffects()) {
        stop()
      } else if (root.notificationSetupAttempts >= 100) {
        console.warn("omarchy-kids: notification service was not ready")
        stop()
      }
    }
  }

  Timer {
    id: shellIntegrationSetup
    interval: 0
    onTriggered: root.syncShellIntegration()
  }

  Timer {
    id: windowSessionSync
    interval: 250
    onTriggered: root.syncWindowSession()
  }

  Timer {
    id: shortcutPolicySync
    interval: 100
    onTriggered: root.syncShortcutPolicy()
  }

  Timer {
    id: windowGuardTimer
    interval: 650
    onTriggered: {
      if (!windowSessionGuard.running) windowSessionGuard.running = true
    }
  }

  onShellChanged: {
    root.scheduleShellIntegration()
    root.scheduleNotificationSetup()
  }
  onManifestChanged: {
    root.scheduleShellIntegration()
    root.scheduleWindowSessionSync()
    root.scheduleShortcutPolicySync()
  }
  onNotificationServiceChanged: root.scheduleNotificationSetup()

  Component.onCompleted: {
    ensureDirectory.running = true
    root.scheduleShellIntegration()
    root.scheduleNotificationSetup()
    root.scheduleWindowSessionSync()
    root.scheduleShortcutPolicySync()
  }

  Component.onDestruction: {
    if (root.pluginRegistry && !root.pluginRegistry.isEnabled(root.pluginId)) {
      root.releaseNotificationPolicy()
      root.releaseShellIntegration()
      if (root.windowSessionTool)
        Quickshell.execDetached([root.windowSessionTool, "exit"])
      if (root.shortcutPolicyTool)
        Quickshell.execDetached([root.shortcutPolicyTool, "exit"])
    }
  }
}
