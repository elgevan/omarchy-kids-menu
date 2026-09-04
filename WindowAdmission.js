function normalizeClass(value) {
  return String(value || "").trim().toLowerCase()
}

function normalizeAddress(value) {
  var address = String(value || "").trim().toLowerCase()
  if (/^[0-9a-f]+$/.test(address)) address = "0x" + address
  return /^0x[0-9a-f]+$/.test(address) ? address : ""
}

function addClass(values, value) {
  var normalized = normalizeClass(value)
  if (normalized && values.indexOf(normalized) < 0) values.push(normalized)
}

function executableClass(command) {
  if (!command || typeof command.length !== "number" || command.length === 0)
    return ""

  var executable = String(command[0] || "")
  var slash = executable.lastIndexOf("/")
  if (slash >= 0) executable = executable.slice(slash + 1)
  if (executable === "env" || executable === "uwsm-app") return ""
  return executable
}

function classCandidates(desktopId, startupClass, command) {
  var values = []
  var id = normalizeClass(desktopId)
  addClass(values, id)
  if (id.slice(-8) === ".desktop") addClass(values, id.slice(0, -8))
  addClass(values, startupClass)
  addClass(values, executableClass(command))
  return values
}

function normalizeClasses(values) {
  var result = []
  for (var i = 0; i < (values || []).length; i++) addClass(result, values[i])
  result.sort()
  return result
}

function eventParts(event, count) {
  try {
    if (event && event.parse) return event.parse(count)
  } catch (error) {
  }
  return String(event && event.data ? event.data : "").split(",")
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeClass: normalizeClass,
    normalizeAddress: normalizeAddress,
    executableClass: executableClass,
    classCandidates: classCandidates,
    normalizeClasses: normalizeClasses,
    eventParts: eventParts
  }
}
