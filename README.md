# Omarchy Kids Mode

Temporarily switch your Omarchy desktop into a simpler space for a child, with only the apps you choose and a separate, persistent browser profile.

Kids Mode is built for sharing your regular computer with a child, not for setting up a device dedicated to kids. Your open apps stay running but out of view, ready for you when Kids Mode ends.

When Kids Mode starts, it:

- Keeps your open apps running but out of view.
- Shows only the apps you choose in the Omarchy menu.
- Uses a separate, persistent Chromium profile.
- Limits shortcuts that would open other apps or settings.
- Turns on Do Not Disturb.

Exiting through the Kids Mode panel invokes Omarchy's lock screen and requires your account password or a configured fingerprint. Apps opened during Kids Mode receive a normal close request, then your apps, workspaces, shortcuts, and notification settings are restored. If an app needs confirmation before closing, Kids Mode stays active so the prompt can be handled safely.

## Requirements and integrations

- Omarchy 4 with the Quattro shell
- Omarchy's Hyprland runtime, lock service, and notification service
- The standard Omarchy command-line tools: `hyprctl`, `jq`, `flock`, Coreutils, and `uwsm-app`
- Chromium installed at `/usr/bin/chromium` for browser and web-app support

No sudo or pkexec is required. The plugin does not install packages or download code, and it performs no network fetches of its own. Apps and websites opened in the separate Chromium profile can use the network normally.

## Install

```bash
omarchy plugin add https://github.com/elgevan/omarchy-kids-menu.git --enable
```

After installation, click the Kids Mode icon on the right side of the bar to open the app manager.

## What it changes

Enabling the plugin adds the Kids Mode manager to the right side of the Omarchy bar and replaces the stock menu button with a compatible version. The original menu position is recorded so it can be restored later.

Starting Kids Mode temporarily:

- Moves your open windows to a private workspace and opens a Kids Mode workspace.
- Limits the Omarchy menu and selected shortcuts to the apps you chose and safe system actions.
- Keeps `Super+1` through `Super+0` available for switching among numbered Kids Mode workspaces, and `Super+Shift+1` through `Super+Shift+0` for moving the focused window there.
- Limits the bar to the Kids Mode controls, workspace strip, Bluetooth, Wi-Fi, volume, display, and power; your exact normal layout is restored on exit.
- Turns on Do Not Disturb while remembering its previous setting.
- Launches supported browsers and web apps with the separate Kids Mode browser profile.

Exiting Kids Mode restores the original windows, workspaces, shortcuts, menu, bar layout, and notification setting. Disabling or removing the plugin also restores the normal shell integration. The shortcut policy is applied at runtime and does not overwrite Hyprland configuration files.

The plugin stores the chosen app list and mode state under `~/.config/omarchy-kids/`, runtime state under `${XDG_STATE_HOME:-~/.local/state}/omarchy-kids/`, and the separate browser profile under `~/.local/share/omarchy-kids/chromium/`.

If shortcut restoration exhausts its automatic retries, the exact failure is retained in `~/.local/state/omarchy-kids/shortcut-restore.json` and marked resolved after a later successful recovery.

## Use

1. Open the Kids Mode manager.
2. Choose the apps available in Kids Mode.
3. Click **Start Kids Mode**.

The top-left Omarchy button opens the normal root menu while Kids Mode is inactive and the chosen app list while Kids Mode is active. Like the stock Omarchy button, right-clicking it opens the terminal while Kids Mode is inactive; the terminal action is suppressed while Kids Mode is active. The default app selections are Google Chrome, Chromium, Omawrite, and Omacalc when those apps are installed.

Some keyboard shortcuts change in Kids Mode. Workspace switching and window movement still work, but shortcuts that open other apps or desktop settings are unavailable until Kids Mode ends.

While Kids Mode is active, the app selection is locked. Open the manager and click **Exit Kids Mode** to return to your desktop. Omarchy will lock the screen and complete the switch after a successful password or fingerprint check. This authentication protects the panel action; software already running as the same Linux user can still modify the plugin's state files or disable the plugin.

## Separate browser profile

Chromium, Google Chrome, and supported web apps use the same separate browser profile each time Kids Mode is active. Its history, bookmarks, extensions, settings, and signed-in websites persist between sessions while staying separate from your regular browser profile.

This is one shared Kids Mode browser profile, not a separate profile for each child.

The profile is stored at:

```text
~/.local/share/omarchy-kids/chromium
```

Kids Mode does not filter websites. Browser content controls should be configured separately if needed.

## What it protects

Kids Mode simplifies the desktop and helps prevent accidental access to your open apps. It is intended for supervised use on a shared account, not as a replacement for a separate Linux user account or system-level parental controls. It is not a security boundary against software running under that account.

## Remove

```bash
omarchy plugin remove io.github.elgevan.omarchy-kids
```

Removing the plugin restores the normal menu, shortcuts, windows, and notification settings. The chosen app list and Kids Mode browser profile are kept so they can be used again after reinstalling.

If a Kids Mode app refuses to close during removal, the plugin keeps your original windows hidden and preserves its recovery snapshot rather than exposing a partially restored desktop. After the cleanup retries finish, normal shortcuts are restored so you are not left in the plugin's shortcut layer. Resolve the app's close prompt, then retry window restoration with:

```bash
"${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/omarchy-kids/tools/window-session" exit
```

If that runtime helper is no longer present, signing out closes the remaining session windows and clears the temporary runtime state.

## Test

Run the plugin checks on an Omarchy system:

```bash
./test/run
```

The optional `test/vm-acceptance` script runs the full flow in a disposable Omarchy VM.
