import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Allowlist.js" as Allowlist
import "KidsBrowser.js" as KidsBrowser
import "ModeState.js" as ModeState
import "NotificationState.js" as NotificationState
import "ShellIntegration.js" as ShellIntegration
import "WindowAdmission.js" as WindowAdmission

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
  property bool modeStateRecoveryPending: false
  property bool modeStateRecoveryFailed: false
  property string modeStateRecoveryCandidate: "unknown"
  property bool modeWritePending: false
  property bool deactivationAuthorized: false
  property string errorRecoveryKind: ""
  property bool notificationStateLoaded: false
  property bool notificationStateManaged: false
  property bool notificationRestoreDnd: false
  property bool notificationApplied: false
  property bool notificationPolicySynced: false
  property int notificationSetupAttempts: 0
  property int hiddenWindowCount: 0
  property string windowSessionError: ""
  property bool windowSessionDesired: false
  property bool windowSessionApplied: false
  property bool windowSessionSynced: false
  property int windowGuardAttemptsRemaining: 0
  property bool windowAdmissionPending: false
  property var pendingLaunchAuthorizations: []
  property var stockMenuRestore: null
  property var barLayoutRestore: null
  property bool shellModeApplied: false
  property bool shellPolicySynced: false
  property bool shellConfigWriteInProgress: false
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
  readonly property var lockService: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("omarchy.lock")
    : null
  readonly property bool notificationsMuted: root.notificationApplied
    && root.notificationService
    && root.notificationService.doNotDisturb === true
  readonly property bool allowlistEditable: root.modeStateLoaded && !root.kidsModeEnabled
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
    var ids = Allowlist.parseSettings(rawText)
    root.replaceAllowedIds(ids === null ? [] : ids, false)
  }

  function loadDefaults() {
    root.replaceAllowedIds(root.defaultDesktopIds, false)
  }

  function isAllowed(desktopId) {
    return Allowlist.contains(root.allowedDesktopIds, desktopId)
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
      if (enabled === true) root.beginActivation()
      else root.beginModeStateRecovery(enabled === false ? "inactive" : "unknown")
      return
    }

    if (root.modeStateRecoveryPending) return

    // Persisted state records recovery intent; they are not an unauthenticated
    // command channel for releasing an active Kids Mode session.
    if (enabled === true && !root.kidsModeEnabled && root.modePhase === "inactive")
      root.beginActivation()
    else if (enabled !== true && root.kidsModeEnabled)
      root.persistModeState()
  }

  function setKidsModeEnabled(enabled) {
    var next = enabled !== false
    if (!root.modeStateLoaded) return
    if (next && !root.kidsModeEnabled && root.modePhase === "inactive")
      root.beginActivation()
  }

  function beginModeStateRecovery(candidate) {
    root.modeStateRecoveryCandidate = candidate || "unknown"
    root.modeStateRecoveryPending = true
    root.modeStateRecoveryFailed = false
    root.errorRecoveryKind = "state-probe"
    root.modePhase = "recovering"
    // Until durable ownership has been checked, do not run any release path.
    root.setEffectiveMode(true)
    if (root.runtimeToolsReady) root.probeModeState()
    else root.prepareRuntimeTools()
  }

  function probeModeState() {
    if (!root.modeStateRecoveryPending || !root.windowSessionTool
        || windowSessionStatus.running)
      return
    windowSessionStatus.running = true
  }

  function finishModeStateRecovery(exitCode, output) {
    if (!root.modeStateRecoveryPending) return
    var result = root.parseWindowSessionOutput(output)
    var status = result ? String(result.status || "") : ""
    if (exitCode !== 0 || !result || !status || status === "unavailable") {
      root.failModeStateRecovery("Could not verify saved Kids Mode state")
      return
    }

    if (status === "inactive") {
      root.modeStateRecoveryPending = false
      root.errorRecoveryKind = ""
      root.initializeInactiveMode()
      if (root.modeStateRecoveryCandidate !== "inactive") root.persistModeState()
      return
    }

    root.modeStateRecoveryPending = false
    root.modeStateRecoveryFailed = false
    root.errorRecoveryKind = ""
    root.modeTransitionError = ""
    root.modePhase = "active"
    root.modeEffectsDesired = true
    root.controlReleaseStarted = false
    root.windowSessionDesired = true
    root.windowSessionApplied = true
    root.windowSessionSynced = true
    root.hiddenWindowCount = Math.max(0, Number(result.hidden || 0))
    root.notificationPolicySynced = false
    root.shellPolicySynced = false
    root.shortcutPolicySynced = false
    root.setEffectiveMode(true)
    root.persistModeState()
    root.scheduleNotificationSetup()
    root.scheduleShellIntegration()
    root.scheduleShortcutPolicySync()
    root.scheduleWindowAdmission(0)
  }

  function failModeStateRecovery(message) {
    root.modeStateRecoveryPending = false
    root.modeStateRecoveryFailed = true
    root.errorRecoveryKind = "state-probe"
    root.modeTransitionError = message || "Could not verify saved Kids Mode state"
    root.modePhase = "error"
    root.modeEffectsDesired = true
    root.windowSessionDesired = true
    root.windowSessionApplied = true
    root.setEffectiveMode(true)
    root.forceSafetyLock()
  }

  function setEffectiveMode(enabled) {
    var next = enabled === true
    if (root.kidsModeEnabled === next) return
    root.kidsModeEnabled = next
    root.kidsModeChanged()
  }

  function initializeInactiveMode() {
    root.modeStateRecoveryPending = false
    root.modeStateRecoveryFailed = false
    root.errorRecoveryKind = ""
    root.modePhase = "inactive"
    root.modeEffectsDesired = false
    root.controlReleaseStarted = false
    root.setEffectiveMode(false)
    root.windowSessionDesired = false
    root.pendingLaunchAuthorizations = []
    root.scheduleNotificationSetup()
    root.scheduleWindowSessionSync()
    root.scheduleShellIntegration()
    root.scheduleShortcutPolicySync()
  }

  function beginActivation() {
    if (!root.modeStateLoaded || root.modePhase !== "inactive") return
    root.modeTransitionError = ""
    root.errorRecoveryKind = ""
    root.windowSessionError = ""
    root.shortcutPolicyError = ""
    root.modePhase = "entering"
    root.modeEffectsDesired = false
    root.controlReleaseStarted = false
    root.pendingLaunchAuthorizations = []
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
    root.windowSessionDesired = false
    root.advanceActivation()
  }

  // Establish each restriction before moving the user into the Kids workspace.
  // This keeps ordinary shortcuts and the stock menu unavailable throughout the
  // transition, and makes rollback unwind a known prefix of the sequence.
  function advanceActivation() {
    if (root.modePhase !== "entering") return
    if (!root.shellPolicySynced || !root.shellModeApplied) {
      root.scheduleShellIntegration()
      return
    }
    if (!root.shortcutPolicySynced || !root.shortcutPolicyApplied) {
      root.scheduleShortcutPolicySync()
      return
    }
    if (!root.notificationPolicySynced || !root.notificationsMuted) {
      root.scheduleNotificationSetup()
      return
    }
    if (!root.windowSessionDesired) {
      root.windowSessionDesired = true
      root.scheduleWindowSessionSync()
      return
    }
    root.maybeCompleteActivation()
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

  function authorizeDeactivation() {
    if (!root.modeStateLoaded || !root.kidsModeEnabled
        || (root.modePhase !== "active" && root.modePhase !== "error"))
      return false
    root.deactivationAuthorized = true
    if (root.modePhase === "active") return root.beginDeactivation()
    return root.retryTransition()
  }

  function beginDeactivation() {
    if (!root.deactivationAuthorized || !root.modeStateLoaded
        || root.modePhase !== "active")
      return false
    root.deactivationAuthorized = false
    root.modeTransitionError = ""
    root.errorRecoveryKind = "authenticated-exit"
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
    return true
  }

  function rollbackActivation(message) {
    if (root.modePhase !== "entering") return
    root.modeTransitionError = message || "Could not start Kids Mode"
    root.activationWaitingForTools = false
    root.modePhase = "rollback"
    root.controlReleaseStarted = false
    root.windowSessionDesired = false
    root.windowSessionSynced = false
    if (!root.windowSessionTool) {
      if (!windowSessionEnter.running && !root.windowSessionApplied) {
        root.windowSessionSynced = true
        root.startControlRelease()
      } else {
        root.modePhase = "error"
      }
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
    root.errorRecoveryKind = root.modePhase === "rollback"
      ? "activation-rollback"
      : "authenticated-exit"
    root.modePhase = "error"
  }

  function retryTransition() {
    if (!root.deactivationAuthorized || root.modePhase !== "error"
        || !root.kidsModeEnabled)
      return false
    root.deactivationAuthorized = false
    root.errorRecoveryKind = "authenticated-exit"
    root.modeTransitionError = ""
    root.windowSessionError = ""
    root.shortcutPolicyError = ""
    root.modePhase = "exiting"
    root.controlReleaseStarted = false
    root.windowSessionDesired = false
    root.windowSessionSynced = false
    if (!root.windowSessionTool) {
      if (!root.windowSessionApplied) {
        root.windowSessionSynced = true
        root.startControlRelease()
      } else {
        root.modePhase = "error"
        root.modeTransitionError = "Runtime helpers are not available yet"
      }
      return false
    }
    root.scheduleWindowSessionSync()
    return true
  }

  function forceSafetyLock() {
    var lock = root.lockService
    if (!lock || typeof lock.beginLock !== "function" || lock.locked === true) return
    if (!lock.beginLock())
      console.warn("omarchy-kids: could not lock after a protection failure")
  }

  function failActiveMode(message) {
    if (root.modePhase !== "active" && root.modePhase !== "error") return
    root.modeTransitionError = message || "Kids Mode protection needs attention"
    root.errorRecoveryKind = "protection-failure"
    root.modePhase = "error"
    root.modeEffectsDesired = true
    root.windowSessionDesired = true
    root.controlReleaseStarted = false
    root.setEffectiveMode(true)
    root.persistModeState()
    root.forceSafetyLock()
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
    root.scheduleWindowAdmission(0)
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
    root.deactivationAuthorized = false
    root.errorRecoveryKind = ""
    root.pendingLaunchAuthorizations = []
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
    root.advanceActivation()
    return true
  }

  function scheduleNotificationSetup() {
    if (root.modeStateRecoveryPending) return
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
    if (!root.modeStateLoaded || root.modeStateRecoveryPending
        || !root.notificationStateLoaded || !root.directoryReady)
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
    if (!root.modeStateLoaded || root.modeStateRecoveryPending
        || !root.windowSessionTool)
      return
    windowSessionSync.restart()
  }

  function syncWindowSession() {
    if (!root.modeStateLoaded || root.modeStateRecoveryPending
        || !root.windowSessionTool
        || windowSessionEnter.running || windowSessionExit.running)
      return

    root.windowSessionError = ""
    if (root.windowSessionDesired) {
      windowSessionEnter.running = true
    } else if (root.modePhase === "rollback"
        || (root.modePhase === "exiting"
          && root.errorRecoveryKind === "authenticated-exit")) {
      windowSessionExit.running = true
    } else {
      root.failActiveMode("Blocked an unauthorized desktop restore")
    }
  }

  function finishWindowSession(action, exitCode, output) {
    var result = root.parseWindowSessionOutput(output)
    var status = result ? String(result.status || "") : ""
    var enteringSucceeded = action === "enter" && exitCode === 0
      && (status === "active" || status === "already-active")
    var restoredSession = status === "restored"
      && Number(result.kidsRemaining || 0) === 0
    var staleSession = status === "stale-session"
      && Number(result.kidsRemaining || 0) === 0
    var alreadyInactive = status === "inactive" && !root.windowSessionApplied
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
        else if (root.modePhase === "active" || root.modePhase === "error")
          root.failActiveMode(root.windowSessionError)
      } else {
        root.windowSessionApplied = true
        root.failDeactivation(root.windowSessionError)
      }
    } else if (action === "enter") {
      root.hiddenWindowCount = Math.max(0, Number(result.hidden || 0))
      root.windowSessionApplied = true
      root.windowSessionSynced = true
      root.advanceActivation()
    } else {
      root.hiddenWindowCount = 0
      root.windowSessionApplied = false
      root.windowSessionSynced = true
      root.startControlRelease()
    }

    if ((action === "enter") !== root.windowSessionDesired)
      windowSessionSync.restart()
  }

  function desktopEntryFor(desktopId) {
    var expected = KidsBrowser.normalizeDesktopId(desktopId)
    var entries = DesktopEntries.applications && DesktopEntries.applications.values
      ? DesktopEntries.applications.values
      : []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (entry && KidsBrowser.normalizeDesktopId(entry.id) === expected)
        return entry
    }
    return null
  }

  function classesForEntry(entry, browserRouted) {
    if (!entry) return []
    var values = WindowAdmission.classCandidates(
      entry.id, entry.startupClass, entry.command)
    if (browserRouted === true)
      values = values.concat(KidsBrowser.windowClasses(
        KidsBrowser.webAppUrl(entry.command, entry.execString)))
    return WindowAdmission.normalizeClasses(values)
  }

  // Used only to migrate an active snapshot written before admissionVersion 1.
  // Current sessions never admit a window from this list without a launch token
  // or an already-recorded process lineage.
  function selectedWindowClasses() {
    var values = []
    var entries = DesktopEntries.applications && DesktopEntries.applications.values
      ? DesktopEntries.applications.values
      : []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (!entry || !root.isAllowed(entry.id)) continue
      values = values.concat(WindowAdmission.classCandidates(
        entry.id, entry.startupClass, entry.command))
      if (KidsBrowser.isBrowser(entry.id)
          || KidsBrowser.webAppUrl(entry.command, entry.execString))
        values = values.concat(KidsBrowser.windowClasses(
          KidsBrowser.webAppUrl(entry.command, entry.execString)))
    }
    return WindowAdmission.normalizeClasses(values)
  }

  function authorizeWindowClasses(classes) {
    if (!root.kidsModeEnabled || root.modePhase !== "active"
        || !root.windowSessionApplied || !root.windowSessionTool)
      return false
    var normalized = WindowAdmission.normalizeClasses(classes)
    if (normalized.length === 0) return false
    var pending = root.pendingLaunchAuthorizations.slice()
    pending.push({classes: normalized, address: "", expiresAt: Date.now() + 15000})
    root.pendingLaunchAuthorizations = pending
    root.windowGuardAttemptsRemaining = 2
    root.scheduleWindowAdmission(80)
    return true
  }

  function authorizeAppLaunch(desktopId, browserRouted) {
    var id = KidsBrowser.normalizeDesktopId(desktopId)
    if (!id || !root.isAllowed(id)) return false
    return root.authorizeWindowClasses(
      root.classesForEntry(root.desktopEntryFor(id), browserRouted === true))
  }

  function authorizeBrowserLaunch() {
    if (!root.shortcutAllowed(["chromium", "google-chrome", "google-chrome-stable"]))
      return false
    return root.authorizeWindowClasses(["chromium"])
  }

  function pendingExpectedWindows() {
    var now = Date.now()
    var pending = []
    var windows = []
    for (var i = 0; i < root.pendingLaunchAuthorizations.length; i++) {
      var authorization = root.pendingLaunchAuthorizations[i]
      if (!authorization || Number(authorization.expiresAt || 0) < now) continue
      pending.push(authorization)
      var address = WindowAdmission.normalizeAddress(authorization.address)
      if (address) windows.push({address: address, classes: authorization.classes || []})
    }
    root.pendingLaunchAuthorizations = pending
    return windows
  }

  function windowAdmissionPolicyText() {
    return JSON.stringify({
      expectedWindows: root.pendingExpectedWindows(),
      bootstrapClasses: root.selectedWindowClasses()
    })
  }

  function scheduleWindowAdmission(delay) {
    if (!root.kidsModeEnabled || !root.windowSessionApplied
        || !root.windowSessionTool || root.modeStateRecoveryPending)
      return
    root.windowAdmissionPending = true
    if (!windowSessionGuard.running) {
      windowGuardTimer.interval = Math.max(0, Number(delay || 0))
      windowGuardTimer.restart()
    }
  }

  function runWindowAdmission() {
    if (windowSessionGuard.running || !root.windowAdmissionPending) return
    root.windowAdmissionPending = false
    windowSessionGuard.command = [
      root.windowSessionTool,
      "guard",
      root.windowAdmissionPolicyText()
    ]
    windowSessionGuard.running = true
  }

  function windowLaunchGuardPending() {
    return root.windowGuardAttemptsRemaining > 0
      || root.windowAdmissionPending || windowGuardTimer.running
      || windowSessionGuard.running
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (["activespecial", "activespecialv2", "activewindowv2", "movewindow",
         "movewindowv2", "workspace", "workspacev2", "focusedmon",
         "monitoradded", "monitoraddedv2"].indexOf(name) >= 0) {
      root.scheduleWindowAdmission(0)
      return
    }
    if (name !== "openwindow") return
    var parts = WindowAdmission.eventParts(event, 4)
    var address = WindowAdmission.normalizeAddress(parts[0])
    var windowClass = WindowAdmission.normalizeClass(parts[2])
    if (!address) return

    var now = Date.now()
    var pending = []
    var bound = false
    for (var i = 0; i < root.pendingLaunchAuthorizations.length; i++) {
      var authorization = root.pendingLaunchAuthorizations[i]
      if (!authorization || Number(authorization.expiresAt || 0) < now) continue
      if (!bound && !authorization.address
          && (authorization.classes || []).indexOf(windowClass) >= 0) {
        authorization = {
          classes: authorization.classes,
          address: address,
          expiresAt: authorization.expiresAt
        }
        bound = true
      }
      pending.push(authorization)
    }
    root.pendingLaunchAuthorizations = pending
    root.scheduleWindowAdmission(40)
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
    if (!root.modeStateLoaded || root.modeStateRecoveryPending
        || !root.shortcutPolicyTool)
      return
    root.shortcutPolicyDesiredSignature = root.shortcutPolicySignature()
    shortcutPolicySync.restart()
  }

  function syncShortcutPolicy() {
    if (!root.modeStateLoaded || root.modeStateRecoveryPending
        || !root.shortcutPolicyTool || root.shortcutPolicyBusy)
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
      console.warn("omarchy-kids: shortcut policy " + action
        + " failed with exit code " + exitCode + ": "
        + root.shortcutPolicyError + "; output: " + String(output || "").trim())
      if (action === "enter") {
        root.shortcutPolicyApplied = false
        if (root.modePhase === "entering")
          root.rollbackActivation(root.shortcutPolicyError)
        else if (root.modePhase === "active" || root.modePhase === "error")
          root.failActiveMode(root.shortcutPolicyError)
      } else {
        root.shortcutPolicyApplied = true
        root.failDeactivation(root.shortcutPolicyError)
      }
    } else {
      root.shortcutPolicyApplied = action === "enter"
      root.shortcutPolicySynced = true
      if (action === "enter") root.advanceActivation()
      else root.maybeCompleteDeactivation()
    }

    if (root.shortcutPolicyRunningSignature !== root.shortcutPolicyDesiredSignature)
      shortcutPolicySync.restart()
  }

  function scheduleShellIntegration() {
    if (root.modeStateRecoveryPending) return
    root.shellSetupAttempts = 0
    shellIntegrationSetup.restart()
  }

  function refreshLiveBar() {
    var liveBar = root.shell && root.shell.bar
    if (!liveBar) return

    // persistShellConfig updates shell.json and shell.barConfig immediately,
    // but an already-mounted bar can miss that change while plugin registry
    // updates are happening in the same turn. Push the new object into the
    // live bar explicitly so Kids Mode never leaves stale widgets on screen.
    if ("barConfig" in liveBar) liveBar.barConfig = root.shell.barConfig
    if (typeof liveBar.applyBarConfig === "function") liveBar.applyBarConfig()
  }

  function kidsShellPolicyMatches() {
    if (!root.shell || !root.shell.shellConfig) return false
    var installedPlugins = root.pluginRegistry
      ? root.pluginRegistry.installedPlugins
      : null
    return ShellIntegration.kidsPluginPolicyMatches(
      root.shell.shellConfig,
      installedPlugins,
      root.pluginId,
      root.managerWidgetId
    )
  }

  function scheduleShellPolicyVerification() {
    if (!root.modeEffectsDesired || root.shellConfigWriteInProgress) return
    shellPolicyVerification.restart()
  }

  function verifyShellPolicy() {
    if (!root.modeEffectsDesired
        || (root.modePhase !== "entering" && root.modePhase !== "active"))
      return
    if (root.kidsShellPolicyMatches()) return

    // FileView reloads and other plugin writes can arrive just after the
    // initial mutation. Treat the settled shell config as authoritative and
    // reapply Kids Mode instead of leaving an unrestricted bar on screen.
    root.shellPolicySynced = false
    root.shellModeApplied = false
    root.scheduleShellIntegration()
  }

  function syncShellIntegration() {
    if (!root.modeStateLoaded || root.modeStateRecoveryPending || !root.shell
        || typeof root.shell.mutateShellConfig !== "function"
        || !root.managerWidgetPath || !root.pluginId)
      return false

    try {
      // Close every currently open plugin surface that is not part of the
      // Kids Mode allowlist before disabling it in shell.json.
      var installedPlugins = root.pluginRegistry
        ? root.pluginRegistry.installedPlugins
        : null
      if (root.modeEffectsDesired && typeof root.shell.hide === "function") {
        var hiddenPluginIds = ShellIntegration.hiddenPluginIds(
          installedPlugins, root.pluginId)
        for (var i = 0; i < hiddenPluginIds.length; i++)
          root.shell.hide(hiddenPluginIds[i])
      }

      root.shellConfigWriteInProgress = true
      try {
        root.shell.mutateShellConfig(function(config) {
          var result = ShellIntegration.activate(
            config,
            root.pluginId,
            root.managerWidgetId,
            root.managerWidgetPath,
            root.modeEffectsDesired,
            installedPlugins
          )
          if (result && result.restore) root.stockMenuRestore = result.restore
          root.barLayoutRestore = result && result.barRestore
            ? result.barRestore
            : null
        })
      } finally {
        root.shellConfigWriteInProgress = false
      }
      root.refreshLiveBar()

      if (root.modeEffectsDesired && !root.kidsShellPolicyMatches())
        return false

      root.shellModeApplied = root.modeEffectsDesired
      root.shellPolicySynced = true
      root.scheduleShellPolicyVerification()
      if (root.modeEffectsDesired) root.advanceActivation()
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
      ShellIntegration.deactivate(
        config,
        root.pluginId,
        root.managerWidgetId,
        root.stockMenuRestore,
        root.barLayoutRestore
      )
    })
    root.refreshLiveBar()
    root.barLayoutRestore = null
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
    onLoadFailed: root.loadDefaults()
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
    command: ["install", "-d", "-m", "0700",
      root.configDir, root.stateDir, root.runtimeToolDir]
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
      } else if (root.modeStateRecoveryPending) {
        root.failModeStateRecovery("Could not prepare Kids Mode state directories")
      } else if (root.modePhase === "active" || root.modePhase === "error") {
        root.failActiveMode("Could not prepare Kids Mode state directories")
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
        if (root.modeStateRecoveryPending)
          root.probeModeState()
        else if (root.modePhase === "entering" && root.activationWaitingForTools)
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
        else if (root.modeStateRecoveryPending)
          root.failModeStateRecovery("Could not prepare runtime helpers")
        else if (root.modePhase === "active" || root.modePhase === "error")
          root.failActiveMode("Could not prepare runtime helpers")
        else if (root.modePhase === "exiting" || root.modePhase === "rollback")
          root.failDeactivation("Could not prepare runtime helpers")
      }
    }
  }

  Process {
    id: windowSessionStatus
    command: root.windowSessionTool ? [root.windowSessionTool, "status"] : []
    stdout: StdioCollector { id: windowSessionStatusOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishModeStateRecovery(exitCode, windowSessionStatusOutput.text)
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
    command: []
    stdout: StdioCollector { id: windowSessionGuardOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var result = root.parseWindowSessionOutput(windowSessionGuardOutput.text)
      if (exitCode !== 0 || !result) {
        if (root.modePhase === "entering")
          root.rollbackActivation("Could not enforce window admission")
        else
          root.failActiveMode("Could not enforce window admission")
      } else if (Number(result.blocked || 0) > 0) {
        Quickshell.execDetached([
          "omarchy-notification-send",
          "A window not approved for Kids Mode remains hidden."
        ])
      }

      if (root.windowGuardAttemptsRemaining > 0)
        root.windowGuardAttemptsRemaining--
      if (root.windowAdmissionPending && root.kidsModeEnabled) {
        root.scheduleWindowAdmission(0)
      } else if (root.windowGuardAttemptsRemaining > 0 && root.kidsModeEnabled) {
        root.scheduleWindowAdmission(1200)
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
        if (root.modePhase === "entering")
          root.rollbackActivation("Could not mute notifications")
        else if (root.modePhase === "active")
          root.failActiveMode("Could not maintain muted notifications")
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
        if (root.modePhase === "entering")
          root.rollbackActivation("Could not update the Omarchy shell")
        else if (root.modePhase === "active")
          root.failActiveMode("Could not maintain the Kids Mode shell")
        else if (root.modePhase === "exiting" || root.modePhase === "rollback")
          root.failDeactivation("Could not restore the Omarchy shell")
      }
    }
  }

  Timer {
    id: shellPolicyVerification
    interval: 350
    onTriggered: root.verifyShellPolicy()
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
    interval: 80
    onTriggered: root.runWindowAdmission()
  }

  onShellChanged: {
    root.scheduleShellIntegration()
    root.scheduleNotificationSetup()
  }

  Connections {
    target: root.shell
    function onShellConfigChanged() { root.scheduleShellPolicyVerification() }
  }
  Connections {
    target: root.pluginRegistry
    function onPluginsChanged() { root.scheduleShellPolicyVerification() }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
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
      try {
        root.releaseNotificationPolicy()
      } catch (error) {
        console.warn("omarchy-kids: could not restore notifications during removal: " + error)
      }
      try {
        root.releaseShellIntegration()
      } catch (error) {
        console.warn("omarchy-kids: could not restore shell integration during removal: " + error)
      }
    }
  }
}
