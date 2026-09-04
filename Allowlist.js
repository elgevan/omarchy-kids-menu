// These are defaults, not launch commands. The menu still resolves each item
// through Omarchy's live DesktopEntries library, so an absent application is
// never shown and no application is installed by this plugin.
var DEFAULT_DESKTOP_IDS = [
  "google-chrome",
  "chromium",
  "omawrite",
  "omacalc"
]

function normalizeDesktopId(value) {
  var id = String(value || "").trim()
  return id.slice(-8) === ".desktop" ? id.slice(0, -8) : id
}

function normalizeIds(values) {
  var source = Array.isArray(values) ? values : []
  var seen = ({})
  var result = []

  for (var i = 0; i < source.length; i++) {
    var id = normalizeDesktopId(source[i])
    if (!id || seen[id]) continue
    seen[id] = true
    result.push(id)
  }

  result.sort()
  return result
}

function defaultIds() {
  return normalizeIds(DEFAULT_DESKTOP_IDS)
}

function parseSettings(rawText) {
  var text = String(rawText || "").trim()
  if (!text) return null

  try {
    var parsed = JSON.parse(text)
    if (parsed && parsed.version === 1 && Array.isArray(parsed.allowedDesktopIds))
      return normalizeIds(parsed.allowedDesktopIds)
  } catch (error) {
  }

  return null
}

function settingsText(values) {
  return JSON.stringify({
    version: 1,
    allowedDesktopIds: normalizeIds(values)
  }, null, 2) + "\n"
}

function idSet(values) {
  var ids = normalizeIds(values)
  var result = ({})
  for (var i = 0; i < ids.length; i++) result[ids[i]] = true
  return result
}

function contains(values, desktopId) {
  return idSet(values)[normalizeDesktopId(desktopId)] === true
}

function filterRows(rows, values) {
  var source = Array.isArray(rows) ? rows : []
  var allowed = idSet(values)
  var result = []

  for (var i = 0; i < source.length; i++) {
    var entry = source[i] && source[i].entry
    if (!entry) continue
    if (allowed[normalizeDesktopId(entry.id)] === true) result.push(source[i])
  }

  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_DESKTOP_IDS: DEFAULT_DESKTOP_IDS,
    normalizeDesktopId: normalizeDesktopId,
    normalizeIds: normalizeIds,
    defaultIds: defaultIds,
    parseSettings: parseSettings,
    settingsText: settingsText,
    contains: contains,
    filterRows: filterRows
  }
}
