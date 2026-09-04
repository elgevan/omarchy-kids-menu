var PLUGIN_ID = "io.github.elgevan.kids-menu"

function menuRoute(kidsModeEnabled) {
  return kidsModeEnabled === true ? "apps" : "root"
}

function commandFor(kidsModeEnabled, terminalRequested) {
  if (terminalRequested === true)
    return kidsModeEnabled === true ? "" : "xdg-terminal-exec"
  return "omarchy-shell shell toggle " + PLUGIN_ID
    + " '{\"menu\":\"" + menuRoute(kidsModeEnabled) + "\"}'"
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    menuRoute: menuRoute,
    commandFor: commandFor
  }
}
