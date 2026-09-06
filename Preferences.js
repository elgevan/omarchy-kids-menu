var DEFAULT_BROWSER_PROTECTION_PROVIDER = "cloudflare-family"

var BROWSER_PROTECTION_PROVIDERS = [
  {
    id: "cloudflare-family",
    label: "Cloudflare Family",
    description: "Blocks malware, phishing, and adult content."
  },
  {
    id: "cleanbrowsing-family",
    label: "CleanBrowsing Family",
    description: "Also blocks proxies and mixed-content sites and enforces SafeSearch."
  },
  {
    id: "adguard-family",
    label: "AdGuard Family",
    description: "Also blocks ads and trackers and enables SafeSearch where possible."
  }
]

function browserProtectionProviders() {
  return BROWSER_PROTECTION_PROVIDERS.map(function(provider) {
    return {
      id: provider.id,
      label: provider.label,
      description: provider.description
    }
  })
}

function normalizeBrowserProtectionProvider(value) {
  var id = String(value || "")
  for (var i = 0; i < BROWSER_PROTECTION_PROVIDERS.length; i++) {
    if (BROWSER_PROTECTION_PROVIDERS[i].id === id) return id
  }
  return DEFAULT_BROWSER_PROTECTION_PROVIDER
}

function normalizePluginIds(values) {
  var source = Array.isArray(values) ? values : []
  var seen = ({})
  var result = []

  for (var i = 0; i < source.length; i++) {
    var id = String(source[i] || "").trim()
    if (!id || id.length > 256 || seen[id]) continue
    seen[id] = true
    result.push(id)
  }

  result.sort()
  return result
}

function parseSettings(rawText) {
  var text = String(rawText || "").trim()
  if (!text || text.length > 65536) return null

  try {
    var parsed = JSON.parse(text)
    if (parsed && parsed.version === 1
        && typeof parsed.browserProtectionProvider === "string"
        && normalizeBrowserProtectionProvider(parsed.browserProtectionProvider)
          === parsed.browserProtectionProvider
        && (parsed.exemptPluginIds === undefined
          || (Array.isArray(parsed.exemptPluginIds)
            && parsed.exemptPluginIds.length <= 128
            && parsed.exemptPluginIds.every(function(value) {
              return typeof value === "string" && value.length > 0
                && value.length <= 256
            })))) {
      return {
        browserProtectionProvider: parsed.browserProtectionProvider,
        exemptPluginIds: normalizePluginIds(parsed.exemptPluginIds)
      }
    }
  } catch (error) {
  }

  return null
}

function settingsText(browserProtectionProvider, exemptPluginIds) {
  return JSON.stringify({
    version: 1,
    browserProtectionProvider: normalizeBrowserProtectionProvider(
      browserProtectionProvider),
    exemptPluginIds: normalizePluginIds(exemptPluginIds)
  }, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_BROWSER_PROTECTION_PROVIDER: DEFAULT_BROWSER_PROTECTION_PROVIDER,
    BROWSER_PROTECTION_PROVIDERS: BROWSER_PROTECTION_PROVIDERS,
    browserProtectionProviders: browserProtectionProviders,
    normalizeBrowserProtectionProvider: normalizeBrowserProtectionProvider,
    normalizePluginIds: normalizePluginIds,
    parseSettings: parseSettings,
    settingsText: settingsText
  }
}
