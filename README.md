# Kids Menu

![Kids Menu](preview.png)

When Kids Menu is on, a child sees only the apps you choose. Your windows are
hidden, shortcuts to other apps and settings are paused, and Chromium and
supported web apps use a separate browser profile with automatic family web
protection.

## Install

Requires Omarchy 4 with the Quattro shell, Chromium, Bubblewrap, and the
standard `hyprctl`, `jq`, `flock`, Coreutils, and `uwsm-app` tools. The plugin
is cloned by the install command below. After installation, it does not install
packages or fetch additional code at runtime, and it requires no elevated
privileges.

```bash
omarchy plugin add https://github.com/elgevan/omarchy-kids-menu.git --enable
```

## Use

1. Click the Kids Menu plugin icon.
2. Search or browse the app tiles, then click the apps the child can use. Use
   **Selected** to review only the chosen apps.
3. Click **Start with _n_ apps**.

The Omarchy icon and `Super + Space` now open only the selected apps. When
finished, open the Kids Menu plugin and click **Exit Kids Menu**. Omarchy asks
for your password or fingerprint and restores your desktop as it was.

Starting Kids Menu temporarily updates the Omarchy shell layout, notification
state, and Hyprland session state. The plugin records the previous values before
applying those changes and restores them when Kids Menu ends.

An app window that was already open before Kids Menu remains part of the adult
session, even when that app is selected for a child. When a selected non-web app
already has a matching adult window, Kids Menu blocks the launch and asks you to
exit Kids Menu and close the adult instance first.
This applies uniformly to non-web apps and prevents an existing document or
signed-in session from crossing into the Kids session.

The separate browser profile is kept between sessions at:

```text
~/.local/share/omarchy-kids/chromium
```

Cloudflare 1.1.1.1 for Families protects the Kids browser and supported web apps
by default. Open the gearbox in the Kids Menu panel to select CleanBrowsing
Family or AdGuard Family instead. All three options work without an account and
block adult content and malicious domains; their additional filtering differs.
The selected provider receives the Kids browser's DNS queries.

Protection is applied as a temporary Chromium policy inside the browser
process; the host's Chromium policies are preserved and no system policy or DNS
setting is changed. If secure DNS cannot be enforced, the browser does not
launch. Other browsers and applications continue using their normal profiles
and system DNS. Changing providers may require closing an already-running Kids
browser before it can reopen with the new policy.

The gearbox also lists user-installed plugin widgets currently placed in the
top-right bar. Select a plugin there to keep its widget and related surfaces
available while Kids Menu is active. Built-in Omarchy widgets are not listed.
Exempt plugins can expose settings or launch other software, so
only exempt plugins you trust a child to use. The normal Omarchy menu cannot be
exempted
because it would bypass the selected-app list.

DNS filtering blocks domains, not individual pages or images on an otherwise
allowed site. It can misclassify sites and cannot guarantee that all unsuitable
material is blocked. Kids Menu is not a replacement for a separate Linux user
or parental controls and is intended for supervised use. The exit check prevents
accidental access, but software running as the same Linux user can still change
the plugin's files, browser settings, or turn it off.

The DNS services are operated by third parties. See each provider's
documentation for filtering and privacy details:

- [Cloudflare 1.1.1.1 for Families](https://developers.cloudflare.com/1.1.1.1/setup/)
- [CleanBrowsing Family Filter](https://cleanbrowsing.org/filters/)
- [AdGuard Family Protection](https://adguard-dns.io/en/public-dns.html)

## Remove

Exit Kids Menu, then run:

```bash
omarchy plugin remove io.github.elgevan.kids-menu
```

Your app list and browser profile are kept in case you reinstall the plugin.

To also delete all saved Kids Menu data, including the app list, browser
history, bookmarks, settings, sign-ins, and internal recovery state, run:

```bash
rm -rf -- "$HOME/.config/omarchy-kids" \
  "$HOME/.local/share/omarchy-kids" \
  "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-kids"
```

This cannot be undone.

## Development

Validate the plugin and run its test suite before publishing changes:

```bash
omarchy plugin validate .
./test/run
```

`test/vm-acceptance` runs the full flow in a disposable Omarchy VM. After
replacing an installed local copy, run `omarchy restart shell`.

## License

[MIT](LICENSE)
