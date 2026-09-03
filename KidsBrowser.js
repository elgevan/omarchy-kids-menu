function normalizeDesktopId(value) {
  var id = String(value || "").trim()
  return id.slice(-8) === ".desktop" ? id.slice(0, -8) : id
}

function isChromium(desktopId) {
  return normalizeDesktopId(desktopId) === "chromium"
}

function profileDir(homeDir) {
  var home = String(homeDir || "").replace(/\/+$/, "")
  return home + "/.local/share/omarchy-kids/chromium"
}

function launchCommand(homeDir) {
  return [
    "uwsm-app",
    "--",
    "/usr/bin/chromium",
    "--user-data-dir=" + profileDir(homeDir),
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-sync"
  ]
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeDesktopId: normalizeDesktopId,
    isChromium: isChromium,
    profileDir: profileDir,
    launchCommand: launchCommand
  }
}
