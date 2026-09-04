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
  property bool runtimeToolsReady: false
  property bool runtimeToolsFailed: false
  property bool activationWaitingForTools: false
  property bool writePending: false
  property bool kidsModeEnabled: false
  property string modePhase: "inactive"
  property string modeTransitionError: ""
  property bool modeEffectsDesired: false
  property bool controlReleaseStarted: false
  property bool modeStateLoaded: false
  property bool modeWritePending: false
  property bool notificationStateLoaded: false
  property bool notificationStateManaged: false
  property bool notificationRestoreDnd: false
  property bool notificationApplied: false
  property bool notificationPolicySynced: false
  property int notificationSetupAttempts: 0
  property int hiddenWindowCount: 0
  property bool windowSessionBusy: false
  property string windowSessionError: ""
  property bool windowSessionDesired: false
  property bool windowSessionApplied: false
  property bool windowSessionSynced: false
  property int windowGuardAttemptsRemaining: 0
  property var stockMenuRestore: null
  property bool shellIntegrationReady: false
  property bool shellModeApplied: false
  property bool shellPolicySynced: false
  property int shellSetupAttempts: 0
  property bool shortcutPolicyApplied: false
  property bool shortcutPolicySynced: false
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
  readonly property string runtimeRoot: Quickshell.env("XDG_RUNTIME_DIR") || stateRoot
  readonly property string runtimeToolDir: runtimeRoot + "/omarchy-kids/tools"
  readonly property var defaultDesktopIds: Allowlist.defaultIds()
  readonly property var notificationService: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("omarchy.notifications")
    : null
  readonly property bool notificationsMuted: root.notificationApplied
    && root.notificationService
    && root.notificationService.doNotDisturb === true
  readonly property bool allowlistEditable: root.modeStateLoaded && !root.kidsModeEnabled
  readonly property bool modeTransitionBusy: root.modePhase === "entering"
    || root.modePhase === "exiting" || root.modePhase === "rollback"
  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id)
    : "io.github.elgevan.omarchy-kids"
  readonly property string managerWidgetId: pluginId + ".manager"
  readonly property string managerWidgetPath: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/ManagerWidget.qml"
    : ""
  readonly property string sourceWindowSessionTool: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/window-session"
    : ""
  readonly property string sourceShortcutPolicyTool: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/shortcut-policy"
    : ""
  readonly property string sourceLifecycleCleanupTool: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) + "/lifecycle-cleanup"
    : ""
  readonly property string windowSessionTool: runtimeToolsReady
    ? runtimeToolDir + "/window-session"
    : ""
  readonly property string shortcutPolicyTool: runtimeToolsReady
    ? runtimeToolDir + "/shortcut-policy"
    : ""
  readonly property string lifecycleCleanupTool: runtimeToolsReady
    ? runtimeToolDir + "/lifecycle-cleanup"
    : ""

  signal allowlistChanged()
  signal kidsModeChanged()

  function prepareRuntimeTools() {
    if (!root.directoryReady || !root.sourceWindowSessionTool
        || !root.sourceShortcutPolicyTool || !root.sourceLifecycleCleanupTool
        || stageRuntimeTools.running)
      return

    root.runtimeToolsReady = false
    root.runtimeToolsFailed = false
    stageRuntimeTools.command = [
      "cp", "--",
      root.sourceWindowSessionTool,
      root.sourceShortcutPolicyTool,
      root.sourceLifecycleCleanupTool,
      root.runtimeToolDir
    ]
    stageRuntimeTools.running = true
  }

  function sameIds(left, right) {
    var a = Allowlist.normalizeIds(left)
    var b = Allowlist.normalizeIds(right)
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
  }

  function replaceAllowedIds(values, persist) {
    if (persist && !root.allowlistEditable) return false
    var normalized = Allowlist.normalizeIds(values)
    var changed = !root.sameIds(root.allowedDesktopIds, normalized)
    root.allowedDesktopIds = normalized
    if (changed) {
      root.allowlistChanged()
      root.scheduleShortcutPolicySync()
    }
    if (persist) root.persist()
    return changed
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
    if (!root.allowlistEditable) return false
    var id = Allowlist.normalizeDesktopId(desktopId)
    if (!id) return false

    var next = root.allowedDesktopIds.slice()
    var index = next.indexOf(id)
    if (allowed && index < 0) next.push(id)
    else if (!allowed && index >= 0) next.splice(index, 1)
    else return false

    return root.replaceAllowedIds(next, true)
  }

  function toggleAllowed(desktopId) {
    if (!root.allowlistEditable) return false
    return root.setAllowed(desktopId, !root.isAllowed(desktopId))
  }

  function resetDefaults() {
    if (!root.allowlistEditable) return false
    return root.replaceAllowedIds(root.defaultDesktopIds, true)
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
    var firstLoad = !root.modeStateLoaded
    root.modeStateLoaded = true
    if (firstLoad) {
      if (enabled) root.beginActivation()
      else root.initializeInactiveMode()
      return
    }

    // Ignore our own committed writes, but continue to honor an external state
    // change using the same transactional path as the panel.
    if (enabled && !root.kidsModeEnabled && root.modePhase === "inactive")
      root.beginActivation()
    else if (!enabled && root.kidsModeEnabled && root.modePhase === "active")
      root.beginDeactivation()
  }

  function setKidsModeEnabled(enabled) {
    var next = enabled !== false
    if (!root.modeStateLoaded) return
    if (next && !root.kidsModeEnabled && root.modePhase === "inactive")
      root.beginActivation()
    else if (!next && root.kidsModeEnabled && root.modePhase === "active")
      root.beginDeactivation()
  }

  function setEffectiveMode(enabled) {
    var next = enabled === true
    if (root.kidsModeEnabled === next) return
    root.kidsModeEnabled = next
    root.kidsModeChanged()
  }

  function initializeInactiveMode() {
    root.modePhase = "inactive"
    root.modeEffectsDesired = false
    root.controlReleaseStarted = false
    root.setEffectiveMode(false)
    root.windowSessionDesired = false
    root.scheduleNotificationSetup()
    root.scheduleWindowSessionSync()
    root.scheduleShellIntegration()
    root.scheduleShortcutPolicySync()
  }

  function beginActivation() {
    if (!root.modeStateLoaded || root.modePhase !== "inactive") return
    root.modeTransitionError = ""
    root.windowSessionError = ""
    root.shortcutPolicyError = ""
    root.modePhase = "entering"
    root.modeEffectsDesired = false
    root.controlReleaseStarted = false
    root.activationWaitingForTools = !root.runtimeToolsReady
    root.setEffectiveMode(true)
    if (!root.runtimeToolsReady) {
      root.prepareRuntimeTools()
      if (root.runtimeToolsFailed)
        root.abortPendingActivation("Could not prepare runtime helpers")
      return
    }
    root.startActivationEffects()
  }

  function startActivationEffects() {
    if (root.modePhase !== "entering" || !root.runtimeToolsReady) return
    root.activationWaitingForTools = false
    root.modeEffectsDesired = true
    root.notificationPolicySynced = false
    root.windowSessionSynced = false
    root.shellPolicySynced = false
    root.shortcutPolicySynced = false
    root.windowSessionDesired = true
    root.scheduleNotificationSetup()
    root.scheduleWindowSessionSync()
    root.scheduleShellIntegration()
    root.scheduleShortcutPolicySync()
  }

  function abortPendingActivation(message) {
    if (root.modePhase !== "entering" || !root.activationWaitingForTools) return
    root.modeTransitionError = message || "Could not start Kids Mode"
    root.activationWaitingForTools = false
    root.modeEffectsDesired = false
    root.windowSessionDesired = false
    root.setEffectiveMode(false)
    root.modePhase = "inactive"
    root.persistModeState()
  }

  function beginDeactivation() {
    if (!root.modeStateLoaded || root.modePhase !== "active") return
    root.modeTransitionError = ""
    root.windowSessionError = ""
    root.shortcutPolicyError = ""
    root.modePhase = "exiting"
    root.controlReleaseStarted = false
    root.windowSessionDesired = false
    root.windowSessionSynced = false
    // Restore windows before relaxing the menu, shortcut, and DND controls.
    // If an app launch is still inside its existing two-pass guard window,
    // let that window settle before the exit helper snapshots Kids clients.
    if (!root.windowLaunchGuardPending()) root.scheduleWindowSessionSync()
  }

  function rollbackActivation(message) {
    if (root.modePhase !== "entering" && root.modePhase !== "active") return
    root.modeTransitionError = message || "Could not start Kids Mode"
    root.activationWaitingForTools = false
    root.modePhase = "rollback"
    root.controlReleaseStarted = false
    root.windowSessionDesired = false
    root.windowSessionSynced = false
    if (!root.windowSessionTool && !windowSessionEnter.running
        && !root.windowSessionApplied) {
      root.windowSessionSynced = true
      root.startControlRelease()
      return
    }
    if (!root.windowSessionTool) {
      root.modePhase = "error"
      return
    }
    root.scheduleWindowSessionSync()
  }

  function startControlRelease() {
    if (root.modePhase !== "exiting" && root.modePhase !== "rollback") return
    root.controlReleaseStarted = true
    root.modeEffectsDesired = false
    root.notificationPolicySynced = false
    root.shellPolicySynced = false
    root.shortcutPolicySynced = false
    if (!root.shortcutPolicyTool && !root.shortcutPolicyApplied)
      root.shortcutPolicySynced = true
    root.scheduleNotificationSetup()
    root.scheduleShellIntegration()
    root.scheduleShortcutPolicySync()
    root.maybeCompleteDeactivation()
  }

  function failDeactivation(message) {
    if (root.modePhase !== "exiting" && root.modePhase !== "rollback") return
    root.modeTransitionError = message || "Could not restore the desktop"
    root.modePhase = "error"
  }

  function retryTransition() {
    if (root.modePhase !== "error" || !root.kidsModeEnabled) return
    root.modeTransitionError = ""
    root.windowSessionError = ""
    root.shortcutPolicyError = ""
    root.modePhase = "exiting"
    root.controlReleaseStarted = false
    root.windowSessionDesired = false
    root.windowSessionSynced = false
    if (!root.windowSessionTool && !root.windowSessionApplied) {
      root.windowSessionSynced = true
      root.startControlRelease()
      return
    }
    if (!root.windowSessionTool) {
      root.modePhase = "error"
      root.modeTransitionError = "Runtime helpers are not available yet"
      return
    }
    root.scheduleWindowSessionSync()
  }

  function maybeCompleteActivation() {
    if (root.modePhase !== "entering") return
    if (!root.notificationPolicySynced || !root.notificationsMuted
        || !root.windowSessionSynced || !root.windowSessionApplied
        || !root.shellPolicySynced || !root.shellModeApplied
        || !root.shortcutPolicySynced || !root.shortcutPolicyApplied)
      return

    root.modePhase = "active"
    root.persistModeState()
  }

  function maybeCompleteDeactivation() {
    if ((root.modePhase !== "exiting" && root.modePhase !== "rollback")
        || !root.controlReleaseStarted)
      return
    if (!root.notificationPolicySynced || root.notificationApplied
        || !root.windowSessionSynced || root.windowSessionApplied
        || !root.shellPolicySynced || root.shellModeApplied
        || !root.shortcutPolicySynced || root.shortcutPolicyApplied)
      return

    var preserveError = root.modePhase === "rollback"
    root.setEffectiveMode(false)
    root.modePhase = "inactive"
    root.controlReleaseStarted = false
    root.persistModeState()
    if (!preserveError) root.modeTransitionError = ""
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
    if (!root.modeEffectsDesired || !root.directoryReady || !root.notificationStateLoaded || !notifications
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
    if (notifications.doNotDisturb !== true) return false
    root.notificationPolicySynced = true
    root.maybeCompleteActivation()
    return true
  }

  function scheduleNotificationSetup() {
    root.notificationSetupAttempts = 0
    notificationSetup.restart()
  }

  function releaseNotificationPolicy() {
    if (!root.notificationStateLoaded || !root.notificationStateManaged) {
      root.notificationApplied = false
      root.notificationPolicySynced = true
      root.maybeCompleteDeactivation()
      return true
    }
    var notifications = root.notificationService
    if (!notifications || notifications.settingsLoaded !== true) {
      console.warn("omarchy-kids: could not restore notification state")
      return false
    }

    notifications.setDoNotDisturb(root.notificationRestoreDnd)
    if (notifications.doNotDisturb !== root.notificationRestoreDnd) return false

    notificationStateFile.setText(NotificationState.stateText(false, false))
    root.notificationStateManaged = false
    root.notificationApplied = false
    root.notificationPolicySynced = true
    root.maybeCompleteDeactivation()
    return true
  }

  function syncModeEffects() {
    if (!root.modeStateLoaded || !root.notificationStateLoaded || !root.directoryReady)
      return false
    return root.modeEffectsDesired
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
    var status = result ? String(result.status || "") : ""
    var enteringSucceeded = action === "enter" && exitCode === 0
      && (status === "active" || status === "already-active")
    var restoredSession = status === "restored"
      && result.workspaceRemoved === true
      && Number(result.kidsRemaining || 0) === 0
    var staleSession = status === "stale-session"
      && result.workspaceRemoved === true
      && Number(result.kidsRemaining || 0) === 0
    var alreadyInactive = status === "inactive" && !root.windowSessionApplied
      && result.workspaceRemoved === true
      && Number(result.kidsRemaining || 0) === 0
    var exitingSucceeded = action === "exit" && exitCode === 0
      && (restoredSession || staleSession || alreadyInactive)

    if (!enteringSucceeded && !exitingSucceeded) {
      root.windowSessionError = action === "enter"
        ? "Could not hide existing windows"
        : "Could not restore hidden windows"
      if (result && Number(result.failed || 0) > 0)
        root.windowSessionError += " (" + Number(result.failed) + " failed)"
      if (action === "enter") {
        // enter-failed means the helper retained an active snapshot so the
        // rollback path can recover every window it touched.
        root.windowSessionApplied = status === "enter-failed"
          || status === "incomplete-session"
        if (root.modePhase === "entering")
          root.rollbackActivation(root.windowSessionError)
      } else {
        root.windowSessionApplied = true
        root.failDeactivation(root.windowSessionError)
      }
    } else if (action === "enter") {
      root.hiddenWindowCount = Math.max(0, Number(result.hidden || 0))
      root.windowSessionApplied = true
      root.windowSessionSynced = true
      root.maybeCompleteActivation()
    } else {
      root.hiddenWindowCount = 0
      root.windowSessionApplied = false
      root.windowSessionSynced = true
      root.startControlRelease()
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

  function windowLaunchGuardPending() {
    return root.windowGuardAttemptsRemaining > 0
      || windowGuardTimer.running || windowSessionGuard.running
  }

  function shortcutAllowed(ids) {
    for (var i = 0; i < ids.length; i++) {
      if (root.isAllowed(ids[i])) return true
    }
    return false
  }

  function shortcutPolicySignature() {
    if (!root.modeEffectsDesired) return "off"
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
    var succeeded = exitCode === 0 && result
      && ((action === "enter" && result.applied === true)
        || (action === "exit" && result.applied === false))

    if (!succeeded) {
      root.shortcutPolicyError = action === "enter"
        ? "Could not filter keyboard shortcuts"
        : "Could not restore keyboard shortcuts"
      if (result && result.error) root.shortcutPolicyError = String(result.error)
      if (action === "enter") {
        root.shortcutPolicyApplied = false
        if (root.modePhase === "entering")
          root.rollbackActivation(root.shortcutPolicyError)
      } else {
        root.shortcutPolicyApplied = true
        root.failDeactivation(root.shortcutPolicyError)
      }
    } else {
      root.shortcutPolicyApplied = action === "enter"
      root.shortcutPolicySynced = true
      if (action === "enter") root.maybeCompleteActivation()
      else root.maybeCompleteDeactivation()
    }

    if (root.shortcutPolicyRunningSignature !== root.shortcutPolicyDesiredSignature)
      shortcutPolicySync.restart()
  }

  function scheduleShellIntegration() {
    root.shellSetupAttempts = 0
    shellIntegrationSetup.restart()
  }

  function syncShellIntegration() {
    if (!root.modeStateLoaded || !root.shell
        || typeof root.shell.mutateShellConfig !== "function"
        || !root.managerWidgetPath || !root.pluginId)
      return false

    try {
      // The stock menu is deliberately unavailable while Kids Mode is active:
      // without clonedFrom, its IPC route cannot be redirected safely.
      if (root.modeEffectsDesired && typeof root.shell.hide === "function")
        root.shell.hide(ShellIntegration.STOCK_MENU_ID)

      root.shell.mutateShellConfig(function(config) {
        var result = ShellIntegration.activate(
          config,
          root.pluginId,
          root.managerWidgetId,
          root.managerWidgetPath,
          root.modeEffectsDesired
        )
        if (result && result.restore) root.stockMenuRestore = result.restore
      })
      root.shellIntegrationReady = true
      root.shellModeApplied = root.modeEffectsDesired
      root.shellPolicySynced = true
      if (root.modeEffectsDesired) root.maybeCompleteActivation()
      else root.maybeCompleteDeactivation()
      return true
    } catch (error) {
      console.warn("omarchy-kids: could not update shell integration: " + error)
      return false
    }
  }

  function releaseShellIntegration() {
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return
    root.shell.mutateShellConfig(function(config) {
      ShellIntegration.deactivate(config, root.managerWidgetId, root.stockMenuRestore)
    })
    root.shellIntegrationReady = false
    root.shellModeApplied = false
    root.shellPolicySynced = true
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
    command: ["mkdir", "-p", root.configDir, root.stateDir, root.runtimeToolDir]
    onExited: function(exitCode) {
      root.directoryReady = exitCode === 0
      if (root.directoryReady) {
        root.flushWrite()
        root.flushModeWrite()
        root.scheduleNotificationSetup()
        root.prepareRuntimeTools()
      } else if (root.modePhase === "entering") {
        if (root.activationWaitingForTools)
          root.abortPendingActivation("Could not prepare Kids Mode state directories")
        else
          root.rollbackActivation("Could not prepare Kids Mode state directories")
      }
    }
  }

  Process {
    id: stageRuntimeTools
    command: []
    onExited: function(exitCode) {
      root.runtimeToolsReady = exitCode === 0
      root.runtimeToolsFailed = exitCode !== 0
      if (root.runtimeToolsReady) {
        if (root.modePhase === "entering" && root.activationWaitingForTools)
          root.startActivationEffects()
        else {
          root.scheduleWindowSessionSync()
          root.scheduleShortcutPolicySync()
        }
      } else {
        root.windowSessionError = "Could not prepare runtime helpers"
        root.shortcutPolicyError = "Could not prepare runtime helpers"
        if (root.modePhase === "entering" && root.activationWaitingForTools)
          root.abortPendingActivation("Could not prepare runtime helpers")
        else if (root.modePhase === "entering")
          root.rollbackActivation("Could not prepare runtime helpers")
        else if (root.modePhase === "exiting" || root.modePhase === "rollback")
          root.failDeactivation("Could not prepare runtime helpers")
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
      } else if ((root.modePhase === "exiting" || root.modePhase === "rollback")
          && !root.windowSessionDesired) {
        root.scheduleWindowSessionSync()
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
        if (root.modePhase === "entering" || root.modePhase === "active")
          root.rollbackActivation("Could not mute notifications")
        else if (root.modePhase === "exiting" || root.modePhase === "rollback")
          root.failDeactivation("Could not restore notification settings")
      }
    }
  }

  Timer {
    id: shellIntegrationSetup
    interval: 100
    repeat: true
    onTriggered: {
      root.shellSetupAttempts++
      if (root.syncShellIntegration()) {
        stop()
      } else if (root.shellSetupAttempts >= 100) {
        console.warn("omarchy-kids: shell integration was not ready")
        stop()
        if (root.modePhase === "entering" || root.modePhase === "active")
          root.rollbackActivation("Could not update the Omarchy shell")
        else if (root.modePhase === "exiting" || root.modePhase === "rollback")
          root.failDeactivation("Could not restore the Omarchy shell")
      }
    }
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
    root.prepareRuntimeTools()
  }
  onNotificationServiceChanged: root.scheduleNotificationSetup()
  onNotificationsMutedChanged: {
    if (root.modeEffectsDesired && !root.notificationsMuted)
      root.scheduleNotificationSetup()
  }

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
      if (root.lifecycleCleanupTool && root.windowSessionTool && root.shortcutPolicyTool) {
        Quickshell.execDetached([
          root.lifecycleCleanupTool,
          root.windowSessionTool,
          root.shortcutPolicyTool
        ])
      } else {
        if (root.windowSessionTool)
          Quickshell.execDetached([root.windowSessionTool, "exit"])
        if (root.shortcutPolicyTool)
          Quickshell.execDetached([root.shortcutPolicyTool, "exit"])
      }
    }
  }
}
