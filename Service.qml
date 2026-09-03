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
  property string omarchyPath: ""
  property var allowedDesktopIds: Allowlist.defaultIds()
  property bool directoryReady: false
  property bool writePending: false

  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy-kids"
  readonly property string configPath: configDir + "/allowed-apps.json"
  readonly property var defaultDesktopIds: Allowlist.defaultIds()

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

  Component.onCompleted: ensureDirectory.running = true
}
