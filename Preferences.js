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

function parseSettings(rawText) {
  var text = String(rawText || "").trim()
  if (!text || text.length > 65536) return null

  try {
    var parsed = JSON.parse(text)
    if (parsed && parsed.version === 1
        && typeof parsed.browserProtectionProvider === "string"
        && normalizeBrowserProtectionProvider(parsed.browserProtectionProvider)
          === parsed.browserProtectionProvider) {
      return {
        browserProtectionProvider: parsed.browserProtectionProvider
      }
    }
  } catch (error) {
  }

  return null
}

function settingsText(browserProtectionProvider) {
  return JSON.stringify({
    version: 1,
    browserProtectionProvider: normalizeBrowserProtectionProvider(
      browserProtectionProvider)
  }, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_BROWSER_PROTECTION_PROVIDER: DEFAULT_BROWSER_PROTECTION_PROVIDER,
    BROWSER_PROTECTION_PROVIDERS: BROWSER_PROTECTION_PROVIDERS,
    browserProtectionProviders: browserProtectionProviders,
    normalizeBrowserProtectionProvider: normalizeBrowserProtectionProvider,
    parseSettings: parseSettings,
    settingsText: settingsText
  }
}
