function parseEnabled(rawText) {
  var text = String(rawText || "").trim()
  if (!text || text.length > 4096) return null

  try {
    var parsed = JSON.parse(text)
    if (parsed && parsed.version === 1 && typeof parsed.enabled === "boolean")
      return parsed.enabled
  } catch (error) {
  }

  return null
}

function stateText(enabled) {
  return JSON.stringify({
    version: 1,
    enabled: enabled === true
  }, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEnabled: parseEnabled,
    stateText: stateText
  }
}
