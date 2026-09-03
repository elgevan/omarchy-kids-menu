import Quickshell
import QtQuick

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

  readonly property string pluginRoot: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : ""

  asynchronous: false
  source: omarchyPath
    ? "file://" + omarchyPath + "/shell/plugins/menu/Menu.qml"
    : ""

  function configureMenu() {
    if (!item) return

    item.omarchyPath = root.omarchyPath
    item.shell = root.shell
    item.manifest = root.manifest

    if (root.pluginRoot) {
      item.defaultMenuPath = root.pluginRoot + "/kids-menu.jsonc"
      item.userMenuPath = Quickshell.env("HOME") + "/.config/omarchy-kids/menu.jsonc"
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
    if (item) {
      configureMenu()
      item.open(payloadJson)
    } else {
      pendingPayload = payloadJson || "{}"
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
