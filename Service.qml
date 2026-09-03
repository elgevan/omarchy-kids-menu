import QtQuick
import Quickshell
import Quickshell.Io
import "Allowlist.js" as Allowlist

// Shared state for the menu and its bar-panel editor. This service only reads
// DesktopEntries and writes the plugin's own allowlist file.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: ""
  property var allowedDesktopIds: Allowlist.defaultIds()
  property bool directoryReady: false
  property bool writePending: false

  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy-kids"
  readonly property string configPath: configDir + "/allowed-apps.json"
  readonly property var defaultDesktopIds: Allowlist.defaultIds()
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

  Process {
    id: ensureDirectory
    command: ["mkdir", "-p", root.configDir]
    onExited: function(exitCode) {
      root.directoryReady = exitCode === 0
      if (root.directoryReady) root.flushWrite()
    }
  }

  Timer {
    id: managerSetup
    interval: 0
    onTriggered: root.ensureManagerWidget()
  }

  onShellChanged: managerSetup.restart()
  onManifestChanged: managerSetup.restart()

  Component.onCompleted: {
    ensureDirectory.running = true
    managerSetup.restart()
  }

  Component.onDestruction: {
    if (root.pluginRegistry && !root.pluginRegistry.isEnabled("omarchy-kids.menu"))
      root.removeManagerWidget()
  }
}
