# Omarchy Kids Menu

This proof-of-concept Omarchy plugin uses its own permanent plugin ID and does not use `omarchy.clonedFrom`. While enabled, its Omarchy-symbol button occupies the stock menu button's bar position and a separate manager remains on the right. Its own **Kids Mode** switch chooses between a filtered kids menu and the normal Omarchy menu. While Kids Mode is on, the root shows only selected installed applications plus Omarchy's Style menu when the style tools are available, and Omarchy's Do Not Disturb mode is enabled. It is a convenience filter, not a security boundary.

The left button opens `io.github.elgevan.omarchy-kids` directly. Because a standalone plugin cannot redirect Omarchy's built-in `omarchy.menu` IPC route, Kids Mode temporarily disables that unrestricted menu. At the same time, a transient Hyprland shortcut layer redirects the normal Menu, Apps, Theme, Background, and browser shortcuts to filtered plugin routes. Stock shortcuts that would directly open hidden apps, adult settings, numbered bar panels, capture/share tools, reminders, notification controls, or other omitted surfaces are temporarily removed. Kids Mode also blocks close-all, laptop-display, monitor-scaling, and touchpad-toggle shortcuts so an accidental key combination cannot discard work or leave the desktop apparently broken. Everyday volume, brightness, media, clipboard, lock, and normal window-navigation controls remain available. Turning Kids Mode off restores the stock IPC route and reloads the user's unchanged Hyprland configuration. Disabling or removing the plugin performs the same restoration, restores the original stock menu bar entry, and removes the manager widget.

There is no Apps submenu. Routes sent to the plugin itself are normalized to the flattened kids root, so both `Super+Space` and `Super+Alt+Space` open the selected apps and optional Style entry while Kids Mode is active.

The initial allowlist is Google Chrome, Chromium, Omawrite, and Omacalc. These are desktop-entry IDs, not launch commands: a default app appears only when it is installed. Style follows the same rule and is omitted when Omarchy's style commands are unavailable.

Browser entries launched from the filtered Kids Mode menu use a persistent local Chromium profile at `~/.local/share/omarchy-kids/chromium`. The Google Chrome entry also routes to this Kids Chromium profile instead of exposing an adult Chrome profile. Omarchy web-app desktop entries added to the allowlist, such as YouTube, launch in app mode with that same Kids profile. Chromium skips its first-run and default-browser prompts and disables browser sync, so no browser login is required. Bookmarks, history, extensions, and local settings remain separate from the user's normal browser profiles and persist across reboots. When Kids Mode is off, browser and web-app entries use Omarchy's normal launch behavior.

The stock browser shortcuts (`Super+Shift+Return`, `Super+Shift+B`, and `Super+Shift+Alt+B`) also launch the isolated Kids Chromium profile whenever a default browser entry remains selected. Omawrite and Omacalc retain guarded versions of their stock shortcuts only while selected, including the same hidden-window protection used by menu launches. Other applications added by a guardian are available from the filtered menu but do not automatically gain global shortcuts.

The normal Omarchy symbol stays in its usual place on the left and opens whichever menu mode is active. The plugin records the original stock button entry in its own bar entry so that shell reloads retain the restore point. A separate child icon is installed with the other plugins on the right; click it to open the Kids Mode manager. A read-only **Active/Inactive** badge reports the current state, while a separate **Start Kids Mode/Exit Kids Mode** action makes the pending change explicit. Starting Kids Mode is immediate. Exiting it opens Omarchy's native lock screen and completes only after a valid account/parent password or configured fingerprint unlocks the session. The plugin never receives or stores the credential.

Starting Kids Mode also records every existing Hyprland application window, silently moves those windows to a hidden parent workspace, and opens a clean named Kids workspace. The applications keep running, so unsaved work is not discarded. After authenticated exit, surviving windows return to their original workspaces and the previously focused window is focused again. Pinned windows are temporarily unpinned and regain their pinned state on exit. A best-effort launch guard keeps a pre-existing single-instance app hidden if starting it from the Kids menu would otherwise reveal the parent's existing window.

When Kids Mode is inactive, any installed desktop app can be added to or removed from the allowlist. While Kids Mode is active, the app list and reset control are read-only; exit Kids Mode with password or fingerprint authentication before changing the selection. The **All**, **Selected**, and **Not Selected** quick filters remain available in either mode for reviewing the current allowlist. Their keyboard shortcuts are `Ctrl+1`, `Ctrl+2`, and `Ctrl+3`; `Ctrl+Shift+K` activates the mode switch. The selection and mode are saved to:

```text
~/.config/omarchy-kids/allowed-apps.json
~/.config/omarchy-kids/mode.json
~/.local/state/omarchy-kids/windows.json
```

When Kids Mode first enables Do Not Disturb, it remembers the existing notification preference in `~/.local/state/omarchy-kids/notifications.json`. Turning Kids Mode off or disabling the plugin restores that preference. Omarchy action confirmations and trusted critical command-line alerts retain the operating system's normal DND bypass behavior.

## Requirements

The plugin targets Omarchy 4's Quattro shell and requires Chromium at `/usr/bin/chromium` for its isolated Kids browser and web-app launches. It otherwise uses commands already supplied by a normal Omarchy installation: `omarchy-shell`, `omarchy-menu-keybindings`, `omarchy-notification-send`, `uwsm-app`, `hyprctl`, `jq`, and `flock`. It has no install hook, requests no elevated privileges, never installs these dependencies itself, and never writes `~/.config/hypr`. Its shortcut changes exist only in the running Hyprland session and are rebuilt from the user's normal configuration on exit.

## Install

Publish or clone this directory as its own Git repository, then run:

```bash
omarchy plugin add https://github.com/elgevan/omarchy-kids-menu.git --enable
```

For local development, copy the directory to `~/.config/omarchy/plugins/io.github.elgevan.omarchy-kids`, then run:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.elgevan.omarchy-kids
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.elgevan.omarchy-kids
```

For normal use, switch modes from the right-side Kids Mode manager. These commands control installation-level plugin activation and are retained for maintenance:

```bash
omarchy plugin disable io.github.elgevan.omarchy-kids
omarchy plugin enable io.github.elgevan.omarchy-kids
```

## Remove

Remove the plugin through Omarchy's standard plugin lifecycle:

```bash
omarchy plugin remove io.github.elgevan.omarchy-kids
```

Omarchy disables the plugin before removing its checkout. During that disable step, the plugin restores the stock menu and bar layout, the normal shortcut set, hidden parent windows, and the notification preference that was active before Kids Mode. The saved allowlist, mode preference, and Kids Chromium profile remain in the user's home directory so they are available after a reinstall.

## Scope

The plugin filters the Omarchy menu, stores desktop-entry IDs and its mode in its own config, routes browser and web-app entries through a separate user-owned Chromium profile while Kids Mode is on, temporarily filters recognized stock Omarchy shortcuts at runtime, temporarily moves existing windows without closing them, temporarily controls Omarchy's Do Not Disturb state, keeps the standard menu symbol on the left, and manages a separate right-side bar control. It removes the menu button's right-click terminal shortcut. It does not install or remove applications, modify persistent Hyprland configuration, restrict terminal commands entered through another route, filter the web, override user-customized shortcuts, or prevent a knowledgeable user from disabling the plugin or reaching the hidden workspace through another route. Authentication protects the in-app Exit action; it is not a system security boundary.

## Testing

Run the static checks on an Omarchy host with:

```bash
./test/run
```

`test/vm-acceptance` is intended for a disposable VM installed from an official Omarchy ISO. It verifies presence-sensitive defaults, transient shortcut filtering and restoration, notification suppression and restoration, adds an installed app through the persisted allowlist, checks that stock menu IPC is blocked only during Kids Mode, confirms the package set is unchanged, and verifies installation-level disable/restore. Set `OMARCHY_KIDS_TEST_PASSWORD` only in a disposable guest to add the wrong-password, valid-password, internal Off, normal-menu, and immediate-On checks.
