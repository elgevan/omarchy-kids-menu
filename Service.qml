import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Allowlist.js" as Allowlist
import "KidsBrowser.js" as KidsBrowser
import "ModeState.js" as ModeState
import "NotificationState.js" as NotificationState
import "Preferences.js" as Preferences
import "ShellIntegration.js" as ShellIntegration
import "ServiceBridge.js" as ServiceBridge
import "WindowAdmission.js" as WindowAdmission

// Shared state for the menu and its bar-panel editor. The service reads
// DesktopEntries, writes plugin-owned state, and temporarily enables Omarchy's
// built-in Do Not Disturb mode while Kids Menu is active.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: ""
  property var allowedDesktopIds: Allowlist.defaultIds()
  property string browserProtectionProvider: Preferences.DEFAULT_BROWSER_PROTECTION_PROVIDER
  property var exemptPluginIds: []
  property var exemptPluginOptions: []
  property string browserProtectionError: ""
  property var pendingBrowserLaunch: null
  property bool browserProtectionTimedOut: false
  property bool preferencesLoaded: false
  property bool preferencesWritePending: false
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
  property bool notificationPolicyBusy: false
  property int notificationSetupAttempts: 0
  property int hiddenWindowCount: 0
  property string windowSessionError: ""
  property bool windowSessionDesired: false
  property bool windowSessionApplied: false
  property bool windowSessionSynced: false
  property bool windowSnapshotLoaded: false
  property var adultWindowClasses: []
  property int windowGuardAttemptsRemaining: 0
  property bool windowAdmissionPending: false
  property var pendingLaunchAuthorizations: []
  property var stockMenuRestore: null
  property var barLayoutRestore: null
  property bool shellModeApplied: false
  property bool shellPolicySynced: false
  property bool shellConfigWriteInProgress: false
  property bool shellConfigLoaded: false
  property var shellConfigSnapshot: null
  property bool pluginCatalogLoaded: false
  property var installedPlugins: ({})
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
  readonly property string preferencesPath: configDir + "/settings.json"
  readonly property string modePath: configDir + "/mode.json"
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || homeDir + "/.local/state"
  readonly property string stateDir: stateRoot + "/omarchy-kids"
  readonly property string notificationStatePath: stateDir + "/notifications.json"
  readonly property string shellRestoreStatePath: stateDir + "/shell.json"
  readonly property string windowStatePath: stateDir + "/windows.json"
  readonly property string runtimeRoot: Quickshell.env("XDG_RUNTIME_DIR") || stateRoot
  readonly property string runtimeToolDir: runtimeRoot + "/omarchy-kids/tools"
  readonly property string shellConfigPath: homeDir + "/.config/omarchy/shell.json"
  readonly property string pluginManifestPath: root.localPath(Qt.resolvedUrl("manifest.json"))
  // Keep application discovery independent of Omarchy's replaceable scoped
  // shell facade. DesktopEntries is Quickshell's public read-only catalog; all
  // launches still pass through this service's admission checks below.
  readonly property var appLibrary: localAppLibrary
  readonly property var defaultDesktopIds: Allowlist.defaultIds()
  readonly property bool notificationsMuted: root.notificationApplied
  readonly property bool allowlistEditable: root.modeStateLoaded && !root.kidsModeEnabled
  readonly property bool settingsEditable: root.modeStateLoaded
    && root.preferencesLoaded && !root.kidsModeEnabled
  readonly property var browserProtectionOptions: Preferences.browserProtectionProviders()
  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id)
    : "io.github.elgevan.kids-menu"
  readonly property string menuWidgetId: pluginId + ".menu"
  readonly property string menuWidgetPath: root.localPath(Qt.resolvedUrl("BarWidget.qml"))
  readonly property string sourceWindowSessionTool: root.localPath(Qt.resolvedUrl("window-session"))
  readonly property string sourceShortcutPolicyTool: root.localPath(Qt.resolvedUrl("shortcut-policy"))
  readonly property string sourceLifecycleCleanupTool: root.localPath(Qt.resolvedUrl("lifecycle-cleanup"))
  readonly property string sourceBrowserProtectionTool: root.localPath(Qt.resolvedUrl("browser-protection"))
  readonly property string sourceNotificationPolicyTool: root.localPath(Qt.resolvedUrl("notification-policy"))
  readonly property string windowSessionTool: runtimeToolsReady
    ? runtimeToolDir + "/window-session"
    : ""
  readonly property string shortcutPolicyTool: runtimeToolsReady
    ? runtimeToolDir + "/shortcut-policy"
    : ""
  readonly property string lifecycleCleanupTool: runtimeToolsReady
    ? runtimeToolDir + "/lifecycle-cleanup"
    : ""
  readonly property string browserProtectionTool: runtimeToolsReady
    ? runtimeToolDir + "/browser-protection"
    : ""
  readonly property string notificationPolicyTool: runtimeToolsReady
    ? runtimeToolDir + "/notification-policy"
    : ""
  readonly property string browserProfileDir: KidsBrowser.profileDir(homeDir)
  readonly property string browserPolicyDir: KidsBrowser.policyDir()
  readonly property int browserProtectionTimeoutMs: 12000

  signal allowlistChanged()
  signal kidsModeChanged()

  QtObject {
    id: localAppLibrary

    signal appsChanged()

    function entryName(entry) {
      return String((entry && entry.name) || (entry && entry.id) || "")
    }

    function entrySubtext(entry) {
      return String((entry && entry.genericName) || "")
    }

    function searchText(entry) {
      var keywords = ""
      try {
        if (entry && entry.keywords && typeof entry.keywords.join === "function")
          keywords = entry.keywords.join(" ")
      } catch (error) {}
      return [entry && entry.name, entry && entry.genericName,
        entry && entry.comment, keywords, entry && entry.id]
        .join(" ").toLowerCase()
    }

    function sortedEntries(query) {
      var values = DesktopEntries.applications.values || []
      var terms = String(query || "").toLowerCase().trim().split(/\s+/)
      var rows = []
      for (var i = 0; i < values.length; i++) {
        var entry = values[i]
        if (!entry || entry.noDisplay || !String(entry.id || "")) continue
        var haystack = searchText(entry)
        var matches = true
        for (var term = 0; term < terms.length; term++) {
          if (terms[term] && haystack.indexOf(terms[term]) < 0) {
            matches = false
            break
          }
        }
        if (matches) rows.push({
          entry: entry,
          key: entryName(entry).toLowerCase()
        })
      }
      rows.sort(function(left, right) {
        return left.key < right.key ? -1 : left.key > right.key ? 1 : 0
      })
      return rows
    }

    function iconSource(icon) {
      var value = String(icon || "")
      if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
        return value
      if (value.charAt(0) === "/") return "file://" + value
      var found = Quickshell.iconPath(value || "application-x-executable", true)
      return found || Quickshell.iconPath("application-x-executable", true)
    }

    function refreshIcons() {}

    function launch(desktopId, name) {
      var id = String(desktopId || "")
      if (!id) return
      Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
    }

    function remove(desktopId, name) {}
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { localAppLibrary.appsChanged() }
  }

  function localPath(url) {
    var value = String(url || "")
    return value.indexOf("file://") === 0
      ? decodeURIComponent(value.slice(7))
      : value
  }

  function prepareRuntimeTools() {
    if (!root.directoryReady || !root.sourceWindowSessionTool
        || !root.sourceShortcutPolicyTool || !root.sourceLifecycleCleanupTool
        || !root.sourceBrowserProtectionTool || !root.sourceNotificationPolicyTool
        || stageRuntimeTools.running)
      return

    root.runtimeToolsReady = false
    root.runtimeToolsFailed = false
    stageRuntimeTools.command = [
      "cp", "--",
      root.sourceWindowSessionTool,
      root.sourceShortcutPolicyTool,
      root.sourceLifecycleCleanupTool,
      root.sourceBrowserProtectionTool,
      root.sourceNotificationPolicyTool,
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

  function loadPreferences(rawText) {
    var values = Preferences.parseSettings(rawText)
    root.browserProtectionProvider = values
      ? values.browserProtectionProvider
      : Preferences.DEFAULT_BROWSER_PROTECTION_PROVIDER
    root.exemptPluginIds = values ? values.exemptPluginIds : []
    root.preferencesLoaded = true
    root.refreshExemptPluginOptions()
  }

  function persistPreferences() {
    root.preferencesWritePending = true
    if (root.directoryReady) {
      root.flushPreferencesWrite()
    } else if (!ensureDirectory.running) {
      ensureDirectory.running = true
    }
  }

  function flushPreferencesWrite() {
    if (!root.preferencesWritePending) return
    root.preferencesWritePending = false
    preferencesFile.setText(Preferences.settingsText(
      root.browserProtectionProvider, root.exemptPluginIds))
  }

  function setBrowserProtectionProvider(providerId) {
    if (!root.settingsEditable) return false
    var provider = Preferences.normalizeBrowserProtectionProvider(providerId)
    if (provider === root.browserProtectionProvider) return false
    root.browserProtectionProvider = provider
    root.persistPreferences()
    return true
  }

  function refreshExemptPluginOptions() {
    root.exemptPluginOptions = ShellIntegration.exemptablePluginOptions(
      root.installedPlugins, root.pluginId, root.shellConfigSnapshot)
  }

  function effectiveExemptPluginIds() {
    var available = ({})
    for (var option = 0; option < root.exemptPluginOptions.length; option++)
      available[root.exemptPluginOptions[option].id] = true
    return Preferences.normalizePluginIds(root.exemptPluginIds).filter(
      function(id) { return available[id] === true })
  }

  function isPluginExempt(pluginId) {
    return Preferences.normalizePluginIds(root.exemptPluginIds)
      .indexOf(String(pluginId || "")) !== -1
  }

  function setPluginExempt(pluginId, exempt) {
    if (!root.settingsEditable) return false
    var id = String(pluginId || "")
    var available = false
    for (var option = 0; option < root.exemptPluginOptions.length; option++) {
      if (root.exemptPluginOptions[option].id === id) {
        available = true
        break
      }
    }
    if (!available) return false

    var next = Preferences.normalizePluginIds(root.exemptPluginIds)
    var index = next.indexOf(id)
    if (exempt && index < 0) next.push(id)
    else if (!exempt && index >= 0) next.splice(index, 1)
    else return false

    root.exemptPluginIds = Preferences.normalizePluginIds(next)
    root.persistPreferences()
    return true
  }

  function togglePluginExempt(pluginId) {
    return root.setPluginExempt(pluginId, !root.isPluginExempt(pluginId))
  }

  function loadShellConfig(rawText) {
    var parsed = null
    try { parsed = JSON.parse(String(rawText || "")) } catch (error) {}
    if (!parsed || typeof parsed !== "object" || parsed.version !== 1) {
      root.shellConfigLoaded = false
      root.shellConfigSnapshot = null
      return
    }
    root.shellConfigSnapshot = parsed
    root.shellConfigLoaded = true
    root.refreshExemptPluginOptions()
    if (!root.shellConfigWriteInProgress) {
      root.scheduleShellIntegration()
      root.scheduleShellPolicyVerification()
    }
  }

  function persistShellConfig(config) {
    root.shellConfigSnapshot = JSON.parse(JSON.stringify(config))
    shellConfigFile.setText(JSON.stringify(root.shellConfigSnapshot, null, 2) + "\n")
  }

  function persistShellRestoreState() {
    shellRestoreStateFile.setText(JSON.stringify({
      version: 1,
      stockMenuRestore: root.stockMenuRestore,
      barLayoutRestore: root.barLayoutRestore
    }, null, 2) + "\n")
  }

  function refreshPluginCatalog() {
    if (!pluginCatalog.running) pluginCatalog.running = true
  }

  function finishPluginCatalog(exitCode, rawText) {
    var rows = null
    try { rows = JSON.parse(String(rawText || "")) } catch (error) {}
    if (exitCode !== 0 || !Array.isArray(rows)) {
      root.pluginCatalogLoaded = false
      return
    }

    var plugins = ({})
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var id = row ? String(row.id || "") : ""
      if (!id) continue
      plugins[id] = {
        id: id,
        name: String(row.name || id),
        kinds: Array.isArray(row.kinds) ? row.kinds.slice() : [],
        __isFirstParty: row.firstParty === true
      }
    }
    root.installedPlugins = plugins
    root.pluginCatalogLoaded = true
    root.refreshExemptPluginOptions()
    root.scheduleShellIntegration()
    root.scheduleShellPolicyVerification()
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
    // command channel for releasing an active Kids Menu session.
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
      root.failModeStateRecovery("Could not verify saved Kids Menu state")
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
    root.modeTransitionError = message || "Could not verify saved Kids Menu state"
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
    root.windowSnapshotLoaded = false
    root.adultWindowClasses = []
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
    root.modeTransitionError = message || "Could not start Kids Menu"
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
    root.cancelBrowserProtection()
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
    root.modeTransitionError = message || "Could not start Kids Menu"
    root.activationWaitingForTools = false
    root.modePhase = "rollback"
    root.controlReleaseStarted = false
    root.cancelBrowserProtection()
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
    Quickshell.execDetached(["omarchy-shell", "lock", "lock"])
  }

  function failActiveMode(message) {
    if (root.modePhase !== "active" && root.modePhase !== "error") return
    root.cancelBrowserProtection()
    root.modeTransitionError = message || "Kids Menu protection needs attention"
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
    return root.runNotificationPolicy("enter")
  }

  function scheduleNotificationSetup() {
    if (root.modeStateRecoveryPending) return
    root.notificationSetupAttempts = 0
    notificationSetup.restart()
  }

  function releaseNotificationPolicy() {
    return root.runNotificationPolicy("exit")
  }

  function runNotificationPolicy(action) {
    if (!root.directoryReady || !root.notificationStateLoaded
        || !root.notificationPolicyTool)
      return false
    var expected = action === "enter"
    if (root.notificationPolicySynced && root.notificationApplied === expected)
      return true
    if (root.notificationPolicyBusy || notificationPolicyApply.running)
      return false
    root.notificationPolicyBusy = true
    notificationPolicyApply.command = [
      root.notificationPolicyTool,
      action,
      root.notificationStatePath
    ]
    notificationPolicyApply.running = true
    return false
  }

  function finishNotificationPolicy(action, exitCode, output) {
    root.notificationPolicyBusy = false
    var result = root.parseWindowSessionOutput(output)
    var expected = action === "enter"
    if (exitCode !== 0 || !result || result.applied !== expected) {
      console.warn("omarchy-kids: notification policy " + action
        + " failed with exit code " + exitCode + ": "
        + String(output || "").trim())
      if (action === "enter" && root.modePhase === "entering")
        root.rollbackActivation("Could not mute notifications")
      else if (action === "enter")
        root.failActiveMode("Could not maintain muted notifications")
      else
        root.failDeactivation("Could not restore notification settings")
      return
    }

    root.notificationStateManaged = expected
    root.notificationRestoreDnd = result.restoreDnd === true
    root.notificationApplied = expected
    root.notificationPolicySynced = true
    notificationSetup.stop()
    if (expected) root.advanceActivation()
    else root.maybeCompleteDeactivation()
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
      root.windowSnapshotLoaded = false
      windowStateFile.reload()
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

  function loadWindowSnapshot(rawText) {
    var classes = WindowAdmission.savedWindowClasses(rawText)
    root.adultWindowClasses = classes === null ? [] : classes
    root.windowSnapshotLoaded = classes !== null
  }

  function notifyAppLaunchBlocked(displayName, message) {
    var label = String(displayName || "This app")
      .replace(/[\r\n\t]+/g, " ").trim().slice(0, 100)
    Quickshell.execDetached([
      "omarchy-notification-send",
      label + ": " + message
    ])
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

  function authorizeAppLaunch(desktopId, browserRouted, displayName) {
    var id = KidsBrowser.normalizeDesktopId(desktopId)
    if (!id || !root.isAllowed(id)) return false
    var classes = root.classesForEntry(
      root.desktopEntryFor(id), browserRouted === true)
    if (browserRouted !== true) {
      if (!root.windowSnapshotLoaded) {
        root.notifyAppLaunchBlocked(displayName || id,
          "Kids Menu is still checking existing windows. Try again in a moment.")
        return false
      }
      if (WindowAdmission.classListsOverlap(classes, root.adultWindowClasses)) {
        root.notifyAppLaunchBlocked(displayName || id,
          "Already open outside Kids Menu. Exit Kids Menu and close it before trying again.")
        return false
      }
    }
    return root.authorizeWindowClasses(classes)
  }

  function authorizeBrowserLaunch() {
    if (!root.shortcutAllowed(["chromium", "google-chrome", "google-chrome-stable"]))
      return false
    return root.authorizeWindowClasses(["chromium"])
  }

  function requestBrowserLaunch(desktopId, appUrl) {
    if (!root.kidsModeEnabled || root.modePhase !== "active"
        || !root.browserProtectionTool || browserProtectionApply.running
        || root.browserProtectionTimedOut || root.pendingBrowserLaunch)
      return false

    var id = KidsBrowser.normalizeDesktopId(desktopId)
    if ((id && !root.isAllowed(id))
        || (!id && !root.shortcutAllowed([
          "chromium", "google-chrome", "google-chrome-stable"
        ])))
      return false

    root.browserProtectionError = ""
    var provider = root.browserProtectionProvider
    root.pendingBrowserLaunch = {
      desktopId: id,
      appUrl: String(appUrl || ""),
      provider: provider,
      profileDir: root.browserProfileDir,
      policyDir: root.browserPolicyDir
    }
    browserProtectionApply.command = [
      root.browserProtectionTool,
      "apply",
      provider,
      root.browserProfileDir,
      root.browserPolicyDir
    ]
    browserProtectionApply.running = true
    browserProtectionTimeout.restart()
    return true
  }

  function failBrowserProtection(message) {
    root.pendingBrowserLaunch = null
    root.browserProtectionError = String(message || "Could not prepare protected browsing")
    console.warn("omarchy-kids: browser protection failed: "
      + root.browserProtectionError)
    Quickshell.execDetached([
      "omarchy-notification-send",
      "Kids browser did not open: " + root.browserProtectionError
    ])
  }

  function cancelBrowserProtection() {
    root.pendingBrowserLaunch = null
    browserProtectionTimeout.stop()
    if (!browserProtectionApply.running) return
    root.browserProtectionTimedOut = true
    browserProtectionApply.running = false
  }

  function finishBrowserProtection(exitCode, output) {
    var launch = root.pendingBrowserLaunch
    root.pendingBrowserLaunch = null
    if (!launch) return

    var result = root.parseWindowSessionOutput(output)
    if (exitCode !== 0 || !result || result.configured !== true
        || String(result.provider || "") !== launch.provider
        || String(result.profileDir || "") !== launch.profileDir
        || String(result.policyDir || "") !== launch.policyDir
        || !result.token || !result.policyPath) {
      root.failBrowserProtection(result && result.error
        ? String(result.error)
        : "Could not prepare protected browsing")
      return
    }

    if (!root.kidsModeEnabled || root.modePhase !== "active") return
    var command = KidsBrowser.launchCommand(root.homeDir, launch.appUrl, {
      token: String(result.token || ""),
      policyPath: String(result.policyPath || "")
    })
    if (command.length === 0) {
      root.failBrowserProtection("Could not build the protected browser command")
      return
    }

    var authorized = launch.desktopId
      ? root.authorizeAppLaunch(launch.desktopId, true)
      : root.authorizeBrowserLaunch()
    if (!authorized) return
    Quickshell.execDetached(command)
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

  function kidsShellPolicyMatches() {
    if (!root.shellConfigLoaded || !root.shellConfigSnapshot) return false
    return ShellIntegration.kidsPluginPolicyMatches(
      root.shellConfigSnapshot,
      root.installedPlugins,
      root.pluginId,
      root.menuWidgetId,
      root.effectiveExemptPluginIds()
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
    // reapply Kids Menu instead of leaving an unrestricted bar on screen.
    root.shellPolicySynced = false
    root.shellModeApplied = false
    root.scheduleShellIntegration()
  }

  function syncShellIntegration() {
    if (!root.modeStateLoaded || root.modeStateRecoveryPending
        || !root.shellConfigLoaded || !root.shellConfigSnapshot
        || (root.modeEffectsDesired && !root.pluginCatalogLoaded)
        || !root.menuWidgetPath || !root.pluginId)
      return false

    try {
      // Close every currently open plugin surface that is not part of the
      // Kids Menu allowlist before disabling it in shell.json.
      if (root.modeEffectsDesired) {
        var hiddenPluginIds = ShellIntegration.hiddenPluginIds(
          root.installedPlugins, root.pluginId, root.effectiveExemptPluginIds())
        for (var i = 0; i < hiddenPluginIds.length; i++)
          Quickshell.execDetached([
            "omarchy-shell", "shell", "hide", hiddenPluginIds[i]
          ])
      }

      root.shellConfigWriteInProgress = true
      try {
        var config = JSON.parse(JSON.stringify(root.shellConfigSnapshot))
        var result = ShellIntegration.activate(
          config,
          root.pluginId,
          root.menuWidgetId,
          root.menuWidgetPath,
          root.modeEffectsDesired,
          root.installedPlugins,
          root.effectiveExemptPluginIds()
        )
        if (result && result.restore) root.stockMenuRestore = result.restore
        root.barLayoutRestore = result && result.barRestore
          ? result.barRestore
          : null
        root.persistShellRestoreState()
        root.persistShellConfig(config)
      } finally {
        root.shellConfigWriteInProgress = false
      }

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
    if (!root.shellConfigLoaded || !root.shellConfigSnapshot) return
    var config = JSON.parse(JSON.stringify(root.shellConfigSnapshot))
    ShellIntegration.deactivate(
      config,
      root.pluginId,
      root.menuWidgetId,
      root.stockMenuRestore,
      root.barLayoutRestore
    )
    root.persistShellConfig(config)
    root.barLayoutRestore = null
    root.persistShellRestoreState()
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
    id: preferencesFile
    path: root.preferencesPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadPreferences(text())
    onLoadFailed: root.loadPreferences("")
    onFileChanged: reload()
  }

  FileView {
    id: shellConfigFile
    path: root.shellConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadShellConfig(text())
    onLoadFailed: root.loadShellConfig("")
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

  FileView {
    id: shellRestoreStateFile
    path: root.shellRestoreStatePath
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: windowStateFile
    path: root.windowStatePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadWindowSnapshot(text())
    onLoadFailed: root.loadWindowSnapshot("")
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
        root.flushPreferencesWrite()
        root.flushModeWrite()
        root.scheduleNotificationSetup()
        root.prepareRuntimeTools()
      } else if (root.modePhase === "entering") {
        if (root.activationWaitingForTools)
          root.abortPendingActivation("Could not prepare Kids Menu state directories")
        else
          root.rollbackActivation("Could not prepare Kids Menu state directories")
      } else if (root.modeStateRecoveryPending) {
        root.failModeStateRecovery("Could not prepare Kids Menu state directories")
      } else if (root.modePhase === "active" || root.modePhase === "error") {
        root.failActiveMode("Could not prepare Kids Menu state directories")
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
    id: pluginCatalog
    command: ["omarchy", "plugin", "list", "--json"]
    stdout: StdioCollector { id: pluginCatalogOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishPluginCatalog(exitCode, pluginCatalogOutput.text)
    }
  }

  Process {
    id: notificationPolicyApply
    command: []
    stdout: StdioCollector { id: notificationPolicyOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var action = notificationPolicyApply.command.length > 1
        ? String(notificationPolicyApply.command[1]) : ""
      root.finishNotificationPolicy(action, exitCode, notificationPolicyOutput.text)
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
          "A window not approved for Kids Menu remains hidden."
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

  Process {
    id: browserProtectionApply
    command: []
    stdout: StdioCollector { id: browserProtectionOutput; waitForEnd: true }
    onExited: function(exitCode) {
      browserProtectionTimeout.stop()
      if (root.browserProtectionTimedOut) {
        root.browserProtectionTimedOut = false
        return
      }
      root.finishBrowserProtection(exitCode, browserProtectionOutput.text)
    }
  }

  Timer {
    id: browserProtectionTimeout
    interval: root.browserProtectionTimeoutMs
    repeat: false
    onTriggered: {
      if (!browserProtectionApply.running) return
      var notifyFailure = root.pendingBrowserLaunch !== null
      root.browserProtectionTimedOut = true
      browserProtectionApply.running = false
      if (notifyFailure)
        root.failBrowserProtection("Browser protection timed out")
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
          root.failActiveMode("Could not maintain the Kids Menu shell")
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
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }
  onManifestChanged: {
    root.refreshPluginCatalog()
    root.scheduleShellIntegration()
    root.prepareRuntimeTools()
  }
  onNotificationsMutedChanged: {
    if (root.modeEffectsDesired && !root.notificationsMuted)
      root.scheduleNotificationSetup()
  }

  Component.onCompleted: {
    ServiceBridge.publish(root)
    root.refreshPluginCatalog()
    ensureDirectory.running = true
    root.scheduleShellIntegration()
    root.scheduleNotificationSetup()
    root.scheduleWindowSessionSync()
    root.scheduleShortcutPolicySync()
  }

  Component.onDestruction: {
    ServiceBridge.clear(root)
    if (root.lifecycleCleanupTool && root.windowSessionTool && root.shortcutPolicyTool) {
      Quickshell.execDetached([
        root.lifecycleCleanupTool,
        root.windowSessionTool,
        root.shortcutPolicyTool,
        root.notificationStatePath,
        root.omarchyPath,
        root.shellRestoreStatePath,
        root.shellConfigPath,
        root.pluginId,
        root.menuWidgetId,
        root.pluginManifestPath
      ])
    }
  }
}
