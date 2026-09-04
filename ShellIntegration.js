var STOCK_MENU_ID = "omarchy.menu"
var WORKSPACES_ID = "omarchy.workspaces"
var RESTORE_KEY = "kidsMenuRestore"
var BAR_RESTORE_KEY = "kidsBarLayoutRestore"
var KIDS_CONTROL_IDS = [
  "omarchy.bluetooth",
  "omarchy.network",
  "omarchy.audio",
  "omarchy.monitor",
  "omarchy.power"
]
var VISIBLE_PLUGIN_KINDS = ["bar-widget", "menu", "overlay", "panel"]
var KIDS_SERVICE_IDS = ["omarchy.media"]

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value))
}

function arrayContains(values, value) {
  return Array.isArray(values) && values.indexOf(value) !== -1
}

function entryId(entry) {
  return String(isObject(entry) ? entry.id || "" : entry || "")
}

function ensureConfigShape(config) {
  if (!isObject(config.bar)) config.bar = ({})
  if (!isObject(config.bar.layout)) config.bar.layout = ({})
  var sections = ["left", "center", "right"]
  for (var i = 0; i < sections.length; i++) {
    if (!Array.isArray(config.bar.layout[sections[i]]))
      config.bar.layout[sections[i]] = []
  }
  if (!Array.isArray(config.plugins)) config.plugins = []
}

function barLocation(config, id) {
  ensureConfigShape(config)
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = config.bar.layout[sections[s]]
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id)
        return { section: sections[s], index: i, entry: entries[i] }
    }
  }
  return null
}

function removeBarEntries(config, id) {
  ensureConfigShape(config)
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    config.bar.layout[sections[s]] = config.bar.layout[sections[s]].filter(function(entry) {
      return entryId(entry) !== id
    })
  }
}

function normalizedRestore(value) {
  if (!isObject(value)) return null
  if (["left", "center", "right"].indexOf(String(value.section || "")) < 0) return null
  if (!isObject(value.entry) || entryId(value.entry) !== STOCK_MENU_ID) return null
  var numericIndex = Math.floor(Number(value.index))
  if (!isFinite(numericIndex) || numericIndex < 0) numericIndex = 0
  return {
    section: String(value.section),
    index: numericIndex,
    entry: cloneJson(value.entry)
  }
}

function normalizedBarRestore(value) {
  if (!isObject(value)) return null
  var sections = ["left", "center", "right"]
  var restore = ({})
  for (var i = 0; i < sections.length; i++) {
    var section = sections[i]
    if (!Array.isArray(value[section])) return null
    restore[section] = cloneJson(value[section])
  }
  if (Array.isArray(value.plugins)) restore.plugins = cloneJson(value.plugins)
  if (value.disabledPlugins === null || Array.isArray(value.disabledPlugins))
    restore.disabledPlugins = cloneJson(value.disabledPlugins)
  return restore
}

function barLayoutSnapshot(config) {
  ensureConfigShape(config)
  return {
    left: cloneJson(config.bar.layout.left),
    center: cloneJson(config.bar.layout.center),
    right: cloneJson(config.bar.layout.right),
    plugins: cloneJson(config.plugins),
    disabledPlugins: Array.isArray(config.disabledPlugins)
      ? cloneJson(config.disabledPlugins)
      : null
  }
}

function upgradeBarRestore(restore, config) {
  if (!restore) return null
  if (!Array.isArray(restore.plugins)) restore.plugins = cloneJson(config.plugins)
  if (!("disabledPlugins" in restore)) {
    var disabled = Array.isArray(config.disabledPlugins)
      ? config.disabledPlugins.filter(function(id) { return String(id) !== STOCK_MENU_ID })
      : []
    restore.disabledPlugins = disabled.length > 0 ? cloneJson(disabled) : null
  }
  return restore
}

function entryFromLayout(layout, id) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout[sections[s]]
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id)
        return isObject(entries[i]) ? cloneJson(entries[i]) : { id: id }
    }
  }
  return { id: id }
}

function workspacesEntryFromLayout(layout) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout[sections[s]]
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (id === WORKSPACES_ID || /[.]workspaces$/.test(id))
        return isObject(entries[i]) ? cloneJson(entries[i]) : { id: id }
    }
  }
  return { id: WORKSPACES_ID }
}

function isAllowedVisiblePlugin(id, pluginId) {
  var key = String(id || "")
  if (key === pluginId || key === WORKSPACES_ID || /[.]workspaces$/.test(key))
    return true
  return KIDS_CONTROL_IDS.indexOf(key) !== -1
}

function manifestHasVisibleSurface(manifest) {
  var kinds = manifest && Array.isArray(manifest.kinds) ? manifest.kinds : []
  for (var i = 0; i < VISIBLE_PLUGIN_KINDS.length; i++) {
    if (arrayContains(kinds, VISIBLE_PLUGIN_KINDS[i])) return true
  }
  return false
}

function hiddenPluginIds(installedPlugins, pluginId) {
  if (!isObject(installedPlugins)) return [STOCK_MENU_ID]
  var hidden = []
  for (var id in installedPlugins) {
    if (!isAllowedVisiblePlugin(id, pluginId)
        && manifestHasVisibleSurface(installedPlugins[id]))
      hidden.push(String(id))
  }
  if (hidden.indexOf(STOCK_MENU_ID) === -1) hidden.push(STOCK_MENU_ID)
  return hidden
}

function applyKidsPluginPolicy(config, installedPlugins, pluginId) {
  ensureConfigShape(config)
  config.plugins = config.plugins.filter(function(entry) {
    return isAllowedVisiblePlugin(entryId(entry), pluginId)
  })

  var disabled = Array.isArray(config.disabledPlugins)
    ? config.disabledPlugins.map(function(id) { return String(id) })
    : []
  disabled = disabled.filter(function(id) {
    return !isAllowedVisiblePlugin(id, pluginId)
  })

  if (isObject(installedPlugins)) {
    for (var id in installedPlugins) {
      var manifest = installedPlugins[id]
      if (manifest && manifest.__isFirstParty === true
          && manifestHasVisibleSurface(manifest)
          && KIDS_SERVICE_IDS.indexOf(String(id)) === -1
          && !isAllowedVisiblePlugin(id, pluginId)
          && disabled.indexOf(String(id)) === -1)
        disabled.push(String(id))
    }
  }
  if (disabled.indexOf(STOCK_MENU_ID) === -1) disabled.push(STOCK_MENU_ID)
  config.disabledPlugins = disabled
}

function kidsPluginPolicyMatches(config, installedPlugins, pluginId, managerId) {
  if (!isObject(config) || !isObject(config.bar) || !isObject(config.bar.layout))
    return false

  var layout = config.bar.layout
  if (!Array.isArray(layout.left) || !Array.isArray(layout.center)
      || !Array.isArray(layout.right))
    return false

  var left = layout.left.map(entryId)
  var right = layout.right.map(entryId)
  if (left.length !== 2 || left[0] !== pluginId
      || (left[1] !== WORKSPACES_ID && !/[.]workspaces$/.test(left[1])))
    return false
  if (layout.center.length !== 0) return false

  var expectedRight = [managerId].concat(KIDS_CONTROL_IDS)
  if (right.length !== expectedRight.length) return false
  for (var r = 0; r < expectedRight.length; r++)
    if (right[r] !== expectedRight[r]) return false

  var plugins = Array.isArray(config.plugins) ? config.plugins : []
  for (var p = 0; p < plugins.length; p++)
    if (!isAllowedVisiblePlugin(entryId(plugins[p]), pluginId)) return false

  var disabled = Array.isArray(config.disabledPlugins)
    ? config.disabledPlugins.map(function(id) { return String(id) })
    : []
  if (disabled.indexOf(STOCK_MENU_ID) === -1) return false
  for (var c = 0; c < KIDS_CONTROL_IDS.length; c++)
    if (disabled.indexOf(KIDS_CONTROL_IDS[c]) !== -1) return false

  if (isObject(installedPlugins)) {
    for (var id in installedPlugins) {
      var manifest = installedPlugins[id]
      if (manifest && manifest.__isFirstParty === true
          && manifestHasVisibleSurface(manifest)
          && KIDS_SERVICE_IDS.indexOf(String(id)) === -1
          && !isAllowedVisiblePlugin(id, pluginId)
          && disabled.indexOf(String(id)) === -1)
        return false
    }
  }
  return true
}

function applyKidsBarLayout(config, pluginId, managerId, managerPath, restore) {
  var pluginLocation = barLocation(config, pluginId)
  var pluginEntry = pluginLocation && isObject(pluginLocation.entry)
    ? cloneJson(pluginLocation.entry)
    : { id: pluginId }
  pluginEntry.id = pluginId
  pluginEntry[BAR_RESTORE_KEY] = cloneJson(restore)

  config.bar.layout.left = [pluginEntry, workspacesEntryFromLayout(restore)]
  config.bar.layout.center = []
  config.bar.layout.right = [managerEntry(managerId, managerPath)]
  for (var i = 0; i < KIDS_CONTROL_IDS.length; i++)
    config.bar.layout.right.push(entryFromLayout(restore, KIDS_CONTROL_IDS[i]))
}

function restoreBarLayout(config, restore, pluginId) {
  config.bar.layout.left = cloneJson(restore.left)
  config.bar.layout.center = cloneJson(restore.center)
  config.bar.layout.right = cloneJson(restore.right)
  if (Array.isArray(restore.plugins)) config.plugins = cloneJson(restore.plugins)
  if (Array.isArray(restore.disabledPlugins))
    config.disabledPlugins = cloneJson(restore.disabledPlugins)
  else if (restore.disabledPlugins === null)
    delete config.disabledPlugins

  var pluginLocation = barLocation(config, pluginId)
  if (pluginLocation && isObject(pluginLocation.entry))
    delete pluginLocation.entry[BAR_RESTORE_KEY]
}

function managerEntry(managerId, managerPath) {
  return { id: managerId, type: "qml", source: managerPath }
}

function ensureManager(config, managerId, managerPath) {
  var existing = barLocation(config, managerId)
  if (existing) {
    config.bar.layout[existing.section][existing.index] = managerEntry(managerId, managerPath)
    return
  }

  var right = config.bar.layout.right
  var insertAt = 0
  for (var i = 0; i < right.length; i++) {
    if (entryId(right[i]) === "omarchy.tray") {
      insertAt = i + 1
      break
    }
  }
  right.splice(insertAt, 0, managerEntry(managerId, managerPath))
}

// Replace the stock menu's bar slot while the plugin is enabled. In Kids Mode,
// also replace the rest of the bar with the small controls allowlist. Both
// restore records travel with the plugin entry so a shell reload cannot lose
// the user's exact normal layout or the stock menu's original slot.
function activate(config, pluginId, managerId, managerPath, kidsModeEnabled, installedPlugins) {
  ensureConfigShape(config)
  var pluginLocation = barLocation(config, pluginId)
  if (!pluginLocation) return { restore: null }

  var pluginEntry = isObject(pluginLocation.entry)
    ? cloneJson(pluginLocation.entry)
    : { id: pluginId }
  pluginEntry.id = pluginId

  var restore = normalizedRestore(pluginEntry[RESTORE_KEY])
  var barRestore = upgradeBarRestore(
    normalizedBarRestore(pluginEntry[BAR_RESTORE_KEY]), config)
  var stockLocation = barLocation(config, STOCK_MENU_ID)
  if (!restore && stockLocation) {
    var restoreIndex = stockLocation.index
    if (pluginLocation.section === stockLocation.section
        && pluginLocation.index < stockLocation.index)
      restoreIndex--
    restore = {
      section: stockLocation.section,
      index: Math.max(0, restoreIndex),
      entry: isObject(stockLocation.entry)
        ? cloneJson(stockLocation.entry)
        : { id: STOCK_MENU_ID }
    }
  }

  if (stockLocation) {
    removeBarEntries(config, pluginId)
    removeBarEntries(config, STOCK_MENU_ID)
    if (restore) pluginEntry[RESTORE_KEY] = cloneJson(restore)
    var destination = restore || {
      section: stockLocation.section,
      index: stockLocation.index,
      entry: { id: STOCK_MENU_ID }
    }
    var target = config.bar.layout[destination.section]
    target.splice(Math.min(destination.index, target.length), 0, pluginEntry)
  } else if (restore && isObject(pluginLocation.entry)) {
    pluginLocation.entry[RESTORE_KEY] = cloneJson(restore)
  }

  ensureManager(config, managerId, managerPath)
  if (kidsModeEnabled === true) {
    if (!barRestore) barRestore = barLayoutSnapshot(config)
    applyKidsBarLayout(config, pluginId, managerId, managerPath, barRestore)
    applyKidsPluginPolicy(config, installedPlugins, pluginId)
  } else if (barRestore) {
    restoreBarLayout(config, barRestore, pluginId)
    ensureManager(config, managerId, managerPath)
  }
  // Outside Kids Mode, leave the user's disabled-plugin preferences intact.
  return {
    restore: restore,
    barRestore: kidsModeEnabled === true ? barRestore : null
  }
}

function deactivate(config, pluginId, managerId, restoreValue, barRestoreValue) {
  ensureConfigShape(config)
  var pluginLocation = barLocation(config, pluginId)
  var embeddedBarRestore = pluginLocation && isObject(pluginLocation.entry)
    ? normalizedBarRestore(pluginLocation.entry[BAR_RESTORE_KEY])
    : null
  var barRestore = embeddedBarRestore || normalizedBarRestore(barRestoreValue)
  if (barRestore) restoreBarLayout(config, barRestore, pluginId)

  removeBarEntries(config, pluginId)
  removeBarEntries(config, managerId)
  config.plugins = config.plugins.filter(function(entry) {
    var id = entryId(entry)
    return id !== pluginId && id !== managerId
  })
  var restore = normalizedRestore(restoreValue)
  if (!restore) return

  removeBarEntries(config, STOCK_MENU_ID)
  var target = config.bar.layout[restore.section]
  target.splice(Math.min(restore.index, target.length), 0, cloneJson(restore.entry))
}

if (typeof module !== "undefined") {
  module.exports = {
    STOCK_MENU_ID: STOCK_MENU_ID,
    WORKSPACES_ID: WORKSPACES_ID,
    RESTORE_KEY: RESTORE_KEY,
    BAR_RESTORE_KEY: BAR_RESTORE_KEY,
    KIDS_CONTROL_IDS: KIDS_CONTROL_IDS,
    KIDS_SERVICE_IDS: KIDS_SERVICE_IDS,
    VISIBLE_PLUGIN_KINDS: VISIBLE_PLUGIN_KINDS,
    entryId: entryId,
    ensureConfigShape: ensureConfigShape,
    barLocation: barLocation,
    normalizedRestore: normalizedRestore,
    normalizedBarRestore: normalizedBarRestore,
    barLayoutSnapshot: barLayoutSnapshot,
    workspacesEntryFromLayout: workspacesEntryFromLayout,
    isAllowedVisiblePlugin: isAllowedVisiblePlugin,
    manifestHasVisibleSurface: manifestHasVisibleSurface,
    hiddenPluginIds: hiddenPluginIds,
    applyKidsPluginPolicy: applyKidsPluginPolicy,
    kidsPluginPolicyMatches: kidsPluginPolicyMatches,
    activate: activate,
    deactivate: deactivate
  }
}
