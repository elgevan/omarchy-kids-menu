function normalizeDesktopId(value) {
  var id = String(value || "").trim()
  return id.slice(-8) === ".desktop" ? id.slice(0, -8) : id
}

function isChromium(desktopId) {
  return normalizeDesktopId(desktopId) === "chromium"
}

function isBrowser(desktopId) {
  var id = normalizeDesktopId(desktopId)
  return isChromium(id) || id === "google-chrome" || id === "google-chrome-stable"
}

function executableName(value) {
  var parts = String(value || "").split("/")
  return parts[parts.length - 1]
}

function urlFromExecString(execString) {
  var match = String(execString || "").match(
    /^\s*(?:\S*\/)?omarchy-launch-webapp\s+(?:"([^"]+)"|'([^']+)'|(\S+))/
  )
  var value = match ? String(match[1] || match[2] || match[3] || "") : ""
  return /^https?:\/\//i.test(value) ? value : ""
}

function webAppUrl(command, execString) {
  var argv = command && typeof command.length === "number" ? command : []
  if (argv.length >= 2 && executableName(argv[0]) === "omarchy-launch-webapp") {
    for (var i = 1; i < argv.length; i++) {
      var value = String(argv[i] || "")
      if (/^https?:\/\//i.test(value)) return value
    }
  }
  return urlFromExecString(execString)
}

function profileDir(homeDir) {
  var home = String(homeDir || "").replace(/\/+$/, "")
  return home + "/.local/share/omarchy-kids/chromium"
}

function launchCommand(homeDir, appUrl) {
  var command = [
    "uwsm-app",
    "--",
    "/usr/bin/chromium",
    "--user-data-dir=" + profileDir(homeDir),
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-sync"
  ]

  var url = String(appUrl || "")
  command.push(url ? "--app=" + url : "--new-window")
  return command
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeDesktopId: normalizeDesktopId,
    isChromium: isChromium,
    isBrowser: isBrowser,
    urlFromExecString: urlFromExecString,
    webAppUrl: webAppUrl,
    profileDir: profileDir,
    launchCommand: launchCommand
  }
}
