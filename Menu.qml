import Quickshell
import QtQuick
import "Allowlist.js" as Allowlist
import "KidsBrowser.js" as KidsBrowser

// Reuse the menu implementation shipped by the running Omarchy installation,
// but point it at this plugin's allowlisted data. This keeps the POC aligned
// with the installed shell instead of vendoring a snapshot of Menu.qml.
Loader {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property string pendingPayload: ""
  property bool hasPendingPayload: false

  readonly property var sourceAppLibrary: shell ? shell.appLibrary : null
  readonly property var allowlistService: shell && typeof shell.serviceFor === "function"
    ? shell.serviceFor("omarchy-kids.menu")
    : null
  readonly property bool kidsModeEnabled: root.allowlistService
    ? root.allowlistService.kidsModeEnabled !== false
    : true

  readonly property string pluginRoot: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : ""
  readonly property string homeDir: Quickshell.env("HOME")

  asynchronous: false
  source: omarchyPath
    ? "file://" + omarchyPath + "/shell/plugins/menu/Menu.qml"
    : ""

  // The stock menu keeps all of its normal launch/icon behavior, but sees a
  // read-only filtered view of DesktopEntries. In particular, remove() is a
  // deliberate no-op: this plugin never uninstalls applications.
  QtObject {
    id: filteredAppLibrary
    signal appsChanged()

    function sortedEntries(query) {
      if (!root.sourceAppLibrary || !root.allowlistService) return []
      return Allowlist.filterRows(
        root.sourceAppLibrary.sortedEntries(query),
        root.allowlistService.allowedDesktopIds
      )
    }

    function entryFor(desktopId) {
      if (!root.sourceAppLibrary) return null
      var expected = KidsBrowser.normalizeDesktopId(desktopId)
      var rows = root.sourceAppLibrary.sortedEntries("")
      for (var i = 0; i < rows.length; i++) {
        var entry = rows[i] ? rows[i].entry : null
        if (entry && KidsBrowser.normalizeDesktopId(entry.id) === expected) return entry
      }
      return null
    }

    function entryName(entry) {
      return root.sourceAppLibrary ? root.sourceAppLibrary.entryName(entry) : ""
    }

    function entrySubtext(entry) {
      return root.sourceAppLibrary ? root.sourceAppLibrary.entrySubtext(entry) : ""
    }

    function iconSource(icon) {
      return root.sourceAppLibrary ? root.sourceAppLibrary.iconSource(icon) : ""
    }

    function launch(desktopId, name) {
      if (!root.sourceAppLibrary) return

      var entry = filteredAppLibrary.entryFor(desktopId)
      var webAppUrl = KidsBrowser.webAppUrl(
        entry ? entry.command : [],
        entry ? entry.execString : ""
      )
      // Browser entries and Omarchy web apps launched from Kids Mode all use
      // one persistent, login-free Chromium profile. This prevents a web-app
      // shortcut such as YouTube from falling through to the adult profile.
      if (KidsBrowser.isBrowser(desktopId) || webAppUrl) {
        if (typeof root.sourceAppLibrary.beginLaunchFeedback === "function")
          root.sourceAppLibrary.beginLaunchFeedback(name)
        Quickshell.execDetached(KidsBrowser.launchCommand(root.homeDir, webAppUrl))
        root.guardAppLaunch()
        return
      }

      root.sourceAppLibrary.launch(desktopId, name)
      root.guardAppLaunch()
    }

    function refreshIcons() {
      if (root.sourceAppLibrary) root.sourceAppLibrary.refreshIcons()
    }

    function remove(desktopId, name) {
      if (root.shell)
        Quickshell.execDetached(["omarchy-notification-send", "Kids Menu only filters apps. Use its bar icon to change the list."])
    }
  }

  QtObject {
    id: filteredShell
    property var appLibrary: filteredAppLibrary
  }

  Connections {
    target: root.sourceAppLibrary
    function onAppsChanged() { filteredAppLibrary.appsChanged() }
  }

  Connections {
    target: root.allowlistService
    function onAllowlistChanged() { filteredAppLibrary.appsChanged() }
    function onKidsModeChanged() { root.configureMenu() }
  }

  function normalizedPayload(payloadJson) {
    var raw = payloadJson || "{}"
    if (!root.kidsModeEnabled) return raw
    try {
      var payload = JSON.parse(raw)
      if (payload && payload.mode !== "select" && payload.mode !== "input") {
        var route = String(payload.initialMenu || payload.menu || "root")
        if (route !== "style" && route.indexOf("style.") !== 0) route = "apps"
        if (payload.initialMenu !== undefined) payload.initialMenu = route
        else payload.menu = route
        return JSON.stringify(payload)
      }
    } catch (error) {
      // Let the stock menu handle malformed or non-JSON payloads as usual.
    }
    return raw
  }

  function guardAppLaunch() {
    if (root.allowlistService
        && typeof root.allowlistService.guardAppLaunch === "function")
      root.allowlistService.guardAppLaunch()
  }

  function configureMenu() {
    if (!item) return

    item.omarchyPath = root.omarchyPath
    item.shell = root.kidsModeEnabled ? filteredShell : root.shell
    item.manifest = root.manifest

    if (root.kidsModeEnabled && root.pluginRoot) {
      item.defaultMenuPath = root.pluginRoot + "/kids-menu.jsonc"
      // App additions are handled by the DesktopEntries allowlist service,
      // not by arbitrary menu actions from Omarchy's normal user extension.
      item.userMenuPath = root.pluginRoot + "/empty-menu.jsonc"
      item.refresh()
    } else if (root.omarchyPath) {
      item.defaultMenuPath = root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
      item.userMenuPath = Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
      item.refresh()
    }

    if (root.hasPendingPayload) {
      var payload = root.pendingPayload
      root.pendingPayload = ""
      root.hasPendingPayload = false
      item.open(payload)
    }
  }

  function open(payloadJson) {
    var payload = normalizedPayload(payloadJson)
    if (item) {
      configureMenu()
      item.open(payload)
    } else {
      pendingPayload = payload
      hasPendingPayload = true
    }
  }

  function close() {
    pendingPayload = ""
    hasPendingPayload = false
    if (item) item.close()
  }

  function refresh() {
    if (!item) return "loading"
    configureMenu()
    return item.refresh()
  }

  function ping() {
    return item ? item.ping() : "loading"
  }

  onLoaded: configureMenu()
  onOmarchyPathChanged: configureMenu()
  onShellChanged: configureMenu()
  onManifestChanged: configureMenu()
}
