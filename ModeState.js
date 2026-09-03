function parseEnabled(rawText) {
  var text = String(rawText || "").trim()
  if (!text) return false

  try {
    var parsed = JSON.parse(text)
    if (parsed && parsed.version === 1 && typeof parsed.enabled === "boolean")
      return parsed.enabled
  } catch (error) {
  }

  return false
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
