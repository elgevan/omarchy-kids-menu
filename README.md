# Kids Mode for Omarchy

Kids Mode gives a child a simple Omarchy desktop with access to only the apps you choose.

When Kids Mode starts, it:

- Hides the parent's open apps without closing them.
- Shows only approved apps in the Omarchy menu.
- Uses a separate Chromium profile for the child.
- Filters shortcuts that would open unapproved apps or settings.
- Turns on Do Not Disturb.

Exiting Kids Mode requires the account password or a configured fingerprint. Apps opened during Kids Mode receive a normal close request, then the parent's apps, workspaces, shortcuts, and notification settings are restored. If an app needs confirmation before closing, Kids Mode stays active so the prompt can be handled safely.

## Requirements

- Omarchy 4 with the Quattro shell
- Chromium installed at `/usr/bin/chromium`

## Install

```bash
omarchy plugin add https://github.com/elgevan/omarchy-kids-menu.git --enable
```

After installation, click the child icon on the right side of the bar to open the Kids Mode manager.

## What it changes

Enabling the plugin adds the Kids Mode manager to the right side of the Omarchy bar and replaces the stock menu slot with a compatible Kids Menu button. The original menu position is recorded so it can be restored later.

Starting Kids Mode temporarily:

- Moves the parent's open windows to a private workspace and opens a Kids workspace.
- Limits the Omarchy menu and selected shortcuts to the approved apps and safe system actions.
- Turns on Do Not Disturb while remembering its previous setting.
- Launches approved browsers and web apps with the separate Kids Chromium profile.

Exiting Kids Mode restores the original windows, workspaces, shortcuts, menu, and notification setting. Disabling or removing the plugin also restores the normal shell integration. The shortcut policy is applied at runtime and does not overwrite Hyprland configuration files.

The plugin stores its allowlist and mode state under `~/.config/omarchy-kids/`, runtime state under `${XDG_STATE_HOME:-~/.local/state}/omarchy-kids/`, and the separate browser profile under `~/.local/share/omarchy-kids/chromium/`.

If shortcut restoration exhausts its automatic retries, the exact failure is retained in `~/.local/state/omarchy-kids/shortcut-restore.json` and marked resolved after a later successful recovery.

## Use

1. Open the Kids Mode manager.
2. Select the apps the child can use.
3. Click **Start Kids Mode**.

The top-left Omarchy button opens the normal root menu while Kids Mode is inactive and the approved app list while Kids Mode is active. Like the stock Omarchy button, right-clicking it opens the terminal while Kids Mode is inactive; the terminal action is suppressed while Kids Mode is active. The default app selections are Google Chrome, Chromium, Omawrite, and Omacalc when those apps are installed.

While Kids Mode is active, the app selection is locked. Open the manager and click **Exit Kids Mode** to return to the parent desktop. Omarchy will lock the screen and complete the switch after a successful password or fingerprint check.

## Separate browser profile

Chromium, Google Chrome, and approved web apps use a dedicated Chromium profile while Kids Mode is active. Its history, bookmarks, extensions, settings, and signed-in websites stay separate from the parent's browser profile.

The profile is stored at:

```text
~/.local/share/omarchy-kids/chromium
```

Kids Mode does not filter websites. Browser content controls should be configured separately if needed.

## What it protects

Kids Mode simplifies the desktop and helps prevent accidental access to the parent's open apps. It is intended for supervised use on a shared account, not as a replacement for a separate Linux user account or system-level parental controls.

## Remove

```bash
omarchy plugin remove io.github.elgevan.omarchy-kids
```

Removing the plugin restores the normal menu, shortcuts, windows, and notification settings. The approved app list and Kids Chromium profile are kept so they can be used again after reinstalling.

## Test

Run the plugin checks on an Omarchy system:

```bash
./test/run
```

The optional `test/vm-acceptance` script runs the full flow in a disposable Omarchy VM.
