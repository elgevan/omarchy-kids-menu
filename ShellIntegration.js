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

function isExemptPlugin(id, exemptPluginIds) {
  var key = String(id || "")
  return key !== STOCK_MENU_ID && key.length > 0
    && arrayContains(exemptPluginIds, key)
}

function isVisiblePluginAllowed(id, pluginId, exemptPluginIds) {
  return isAllowedVisiblePlugin(id, pluginId)
    || isExemptPlugin(id, exemptPluginIds)
}

function manifestHasVisibleSurface(manifest) {
  var kinds = manifest && Array.isArray(manifest.kinds) ? manifest.kinds : []
  for (var i = 0; i < VISIBLE_PLUGIN_KINDS.length; i++) {
    if (arrayContains(kinds, VISIBLE_PLUGIN_KINDS[i])) return true
  }
  return false
}

function exemptablePluginOptions(installedPlugins, pluginId, config) {
  if (!isObject(installedPlugins) || !isObject(config)
      || !isObject(config.bar) || !isObject(config.bar.layout)
      || !Array.isArray(config.bar.layout.right))
    return []
  var pluginLocation = barLocation(config, pluginId)
  var restore = pluginLocation && isObject(pluginLocation.entry)
    ? normalizedBarRestore(pluginLocation.entry[BAR_RESTORE_KEY])
    : null
  var rightBarIds = (restore ? restore.right : config.bar.layout.right).map(entryId)
  var options = []
  for (var id in installedPlugins) {
    var manifest = installedPlugins[id]
    if (id === STOCK_MENU_ID || isAllowedVisiblePlugin(id, pluginId)
        || !manifest || manifest.__isFirstParty === true
        || !arrayContains(manifest.kinds, "bar-widget")
        || rightBarIds.indexOf(String(id)) === -1)
      continue
    options.push({
      id: String(id),
      label: String(manifest && manifest.name ? manifest.name : id)
    })
  }
  options.sort(function(left, right) {
    var byLabel = left.label.localeCompare(right.label)
    return byLabel !== 0 ? byLabel : left.id.localeCompare(right.id)
  })
  return options
}

function hiddenPluginIds(installedPlugins, pluginId, exemptPluginIds) {
  if (!isObject(installedPlugins)) return [STOCK_MENU_ID]
  var hidden = []
  for (var id in installedPlugins) {
    if (!isVisiblePluginAllowed(id, pluginId, exemptPluginIds)
        && manifestHasVisibleSurface(installedPlugins[id]))
      hidden.push(String(id))
  }
  if (hidden.indexOf(STOCK_MENU_ID) === -1) hidden.push(STOCK_MENU_ID)
  return hidden
}

function applyKidsPluginPolicy(config, installedPlugins, pluginId,
                               exemptPluginIds, restore) {
  ensureConfigShape(config)
  var originalPlugins = restore && Array.isArray(restore.plugins)
    ? restore.plugins : config.plugins
  config.plugins = originalPlugins.filter(function(entry) {
    return isVisiblePluginAllowed(entryId(entry), pluginId, exemptPluginIds)
  }).map(cloneJson)

  var originallyDisabled = restore && Array.isArray(restore.disabledPlugins)
    ? restore.disabledPlugins.map(function(id) { return String(id) })
    : []
  var disabled = restore && (restore.disabledPlugins === null
      || Array.isArray(restore.disabledPlugins))
    ? originallyDisabled.slice()
    : Array.isArray(config.disabledPlugins)
      ? config.disabledPlugins.map(function(id) { return String(id) })
      : []
  disabled = disabled.filter(function(id) {
    if (isAllowedVisiblePlugin(id, pluginId)) return false
    if (isExemptPlugin(id, exemptPluginIds))
      return originallyDisabled.indexOf(id) !== -1
    return true
  })

  if (isObject(installedPlugins)) {
    for (var id in installedPlugins) {
      var manifest = installedPlugins[id]
      if (manifest && manifest.__isFirstParty === true
          && manifestHasVisibleSurface(manifest)
          && KIDS_SERVICE_IDS.indexOf(String(id)) === -1
          && !isVisiblePluginAllowed(id, pluginId, exemptPluginIds)
          && disabled.indexOf(String(id)) === -1)
        disabled.push(String(id))
    }
  }
  if (disabled.indexOf(STOCK_MENU_ID) === -1) disabled.push(STOCK_MENU_ID)
  config.disabledPlugins = disabled
}

function kidsPluginPolicyMatches(config, installedPlugins, pluginId, managerId,
                                 exemptPluginIds) {
  if (!isObject(config) || !isObject(config.bar) || !isObject(config.bar.layout))
    return false

  var layout = config.bar.layout
  if (!Array.isArray(layout.left) || !Array.isArray(layout.center)
      || !Array.isArray(layout.right))
    return false

  var pluginLocation = barLocation(config, pluginId)
  var restore = pluginLocation && isObject(pluginLocation.entry)
    ? normalizedBarRestore(pluginLocation.entry[BAR_RESTORE_KEY])
    : null
  if (!restore) return false
  var expectedLayout = kidsBarLayout(
    restore, pluginId, managerId, "", exemptPluginIds)
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var section = sections[s]
    var actualIds = layout[section].map(entryId)
    var expectedIds = expectedLayout[section].map(entryId)
    if (actualIds.length !== expectedIds.length) return false
    for (var e = 0; e < expectedIds.length; e++)
      if (actualIds[e] !== expectedIds[e]) return false
  }

  var plugins = Array.isArray(config.plugins) ? config.plugins : []
  var expectedPlugins = Array.isArray(restore.plugins)
    ? restore.plugins.filter(function(entry) {
        return isVisiblePluginAllowed(entryId(entry), pluginId, exemptPluginIds)
      })
    : []
  if (plugins.length !== expectedPlugins.length) return false
  for (var p = 0; p < plugins.length; p++) {
    if (entryId(plugins[p]) !== entryId(expectedPlugins[p])) return false
  }

  var disabled = Array.isArray(config.disabledPlugins)
    ? config.disabledPlugins.map(function(id) { return String(id) })
    : []
  if (disabled.indexOf(STOCK_MENU_ID) === -1) return false
  for (var c = 0; c < KIDS_CONTROL_IDS.length; c++)
    if (disabled.indexOf(KIDS_CONTROL_IDS[c]) !== -1) return false

  var originallyDisabled = Array.isArray(restore.disabledPlugins)
    ? restore.disabledPlugins.map(function(id) { return String(id) })
    : []
  var exemptions = Array.isArray(exemptPluginIds) ? exemptPluginIds : []
  for (var x = 0; x < exemptions.length; x++) {
    var exemptId = String(exemptions[x])
    if (exemptId !== STOCK_MENU_ID
        && originallyDisabled.indexOf(exemptId) === -1
        && disabled.indexOf(exemptId) !== -1)
      return false
  }

  if (isObject(installedPlugins)) {
    for (var id in installedPlugins) {
      var manifest = installedPlugins[id]
      if (manifest && manifest.__isFirstParty === true
          && manifestHasVisibleSurface(manifest)
          && KIDS_SERVICE_IDS.indexOf(String(id)) === -1
          && !isVisiblePluginAllowed(id, pluginId, exemptPluginIds)
          && disabled.indexOf(String(id)) === -1)
        return false
    }
  }
  return true
}

function appendExemptBarEntries(layout, restore, pluginId, exemptPluginIds) {
  var sections = ["left", "center", "right"]
  var present = ({})
  for (var s = 0; s < sections.length; s++) {
    var current = layout[sections[s]]
    for (var i = 0; i < current.length; i++) present[entryId(current[i])] = true
  }

  for (var r = 0; r < sections.length; r++) {
    var section = sections[r]
    var entries = restore[section]
    for (var e = 0; e < entries.length; e++) {
      var id = entryId(entries[e])
      if (!present[id] && isExemptPlugin(id, exemptPluginIds)
          && id !== pluginId) {
        layout[section].push(cloneJson(entries[e]))
        present[id] = true
      }
    }
  }
}

function kidsBarLayout(restore, pluginId, managerId, managerPath,
                       exemptPluginIds) {
  var layout = {
    left: [managerEntry(managerId, managerPath), workspacesEntryFromLayout(restore)],
    center: [],
    right: [{id: pluginId}]
  }
  for (var i = 0; i < KIDS_CONTROL_IDS.length; i++)
    layout.right.push(entryFromLayout(restore, KIDS_CONTROL_IDS[i]))
  appendExemptBarEntries(layout, restore, pluginId, exemptPluginIds)
  return layout
}

function applyKidsBarLayout(config, pluginId, managerId, managerPath, restore,
                            exemptPluginIds) {
  var pluginLocation = barLocation(config, pluginId)
  var layout = kidsBarLayout(
    restore, pluginId, managerId, managerPath, exemptPluginIds)
  var pluginEntry = pluginLocation && isObject(pluginLocation.entry)
    ? cloneJson(pluginLocation.entry) : layout.right[0]
  pluginEntry.id = pluginId
  pluginEntry[BAR_RESTORE_KEY] = cloneJson(restore)
  layout.right[0] = pluginEntry
  config.bar.layout.left = layout.left
  config.bar.layout.center = layout.center
  config.bar.layout.right = layout.right
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

function ensureRegisteredManager(config, pluginId, pluginEntry) {
  removeBarEntries(config, pluginId)
  var right = config.bar.layout.right
  var insertAt = 0
  for (var i = 0; i < right.length; i++) {
    if (entryId(right[i]) === "omarchy.tray") {
      insertAt = i + 1
      break
    }
  }
  right.splice(insertAt, 0, pluginEntry)
}

// Replace the stock menu's bar slot while the plugin is enabled. In Kids Menu,
// also replace the rest of the bar with the small controls allowlist. Both
// restore records travel with the plugin entry so a shell reload cannot lose
// the user's exact normal layout or the stock menu's original slot.
function activate(config, pluginId, managerId, managerPath, kidsModeEnabled,
                  installedPlugins, exemptPluginIds) {
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

  // Leaving Kids Menu restores the complete inactive layout captured at
  // entry. It already contains the inline menu button and registered manager.
  if (kidsModeEnabled !== true && barRestore) {
    restoreBarLayout(config, barRestore, pluginId)
    return { restore: restore, barRestore: null }
  }

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

  var destination = restore || (stockLocation ? {
    section: stockLocation.section,
    index: stockLocation.index,
    entry: { id: STOCK_MENU_ID }
  } : null)
  removeBarEntries(config, managerId)
  removeBarEntries(config, STOCK_MENU_ID)
  if (restore) pluginEntry[RESTORE_KEY] = cloneJson(restore)
  if (destination) {
    var target = config.bar.layout[destination.section]
    target.splice(
      Math.min(destination.index, target.length),
      0,
      managerEntry(managerId, managerPath)
    )
  }
  ensureRegisteredManager(config, pluginId, pluginEntry)

  if (kidsModeEnabled === true) {
    if (!barRestore) barRestore = barLayoutSnapshot(config)
    applyKidsBarLayout(config, pluginId, managerId, managerPath, barRestore,
      exemptPluginIds)
    applyKidsPluginPolicy(config, installedPlugins, pluginId, exemptPluginIds,
      barRestore)
  }
  // Outside Kids Menu, leave the user's disabled-plugin preferences intact.
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
    isExemptPlugin: isExemptPlugin,
    isVisiblePluginAllowed: isVisiblePluginAllowed,
    manifestHasVisibleSurface: manifestHasVisibleSurface,
    exemptablePluginOptions: exemptablePluginOptions,
    hiddenPluginIds: hiddenPluginIds,
    applyKidsPluginPolicy: applyKidsPluginPolicy,
    kidsPluginPolicyMatches: kidsPluginPolicyMatches,
    appendExemptBarEntries: appendExemptBarEntries,
    kidsBarLayout: kidsBarLayout,
    activate: activate,
    deactivate: deactivate
  }
}
