# Omarchy Kids Menu

This proof-of-concept Omarchy plugin replaces the stock `omarchy.menu` while installed and enabled. Its own **Kids Mode** switch chooses between a filtered kids menu and the normal Omarchy menu. While Kids Mode is on, the root shows only selected installed applications plus Omarchy's Style menu when the style tools are available, and Omarchy's Do Not Disturb mode is enabled. It is a convenience filter, not a security boundary.

The plugin uses Omarchy's `omarchy.clonedFrom` contract, so existing menu keybindings and IPC calls continue targeting `omarchy.menu`. Disabling or removing the whole plugin still restores the stock menu automatically.

There is no Apps submenu. The plugin redirects Omarchy's stock Apps-menu shortcut (`Super+Alt+Space`) and blocked stock routes to the flattened kids root.

The initial allowlist is Google Chrome, Chromium, Omawrite, and Omacalc. These are desktop-entry IDs, not launch commands: a default app appears only when it is installed. Style follows the same rule and is omitted when Omarchy's style commands are unavailable.

Chromium launched from the filtered Kids Mode menu uses its own persistent local profile at `~/.local/share/omarchy-kids/chromium`. It skips Chromium's first-run and default-browser prompts and disables browser sync, so no browser login is required. Its bookmarks, history, extensions, and local settings remain separate from the user's normal Chromium profile and persist across reboots. When Kids Mode is off, Chromium launches normally through its system desktop entry.

The normal Omarchy symbol stays in its usual place on the left and opens whichever menu mode is active. A separate child icon is installed with the other plugins on the right; click it to open the Kids Mode manager. A read-only **Active/Inactive** badge reports the current state, while a separate **Start Kids Mode/Exit Kids Mode** action makes the pending change explicit. Starting Kids Mode is immediate. Exiting it opens Omarchy's native lock screen and completes only after a valid account/parent password or configured fingerprint unlocks the session. The plugin never receives or stores the credential.

Starting Kids Mode also records every existing Hyprland application window, silently moves those windows to a hidden parent workspace, and opens a clean named Kids workspace. The applications keep running, so unsaved work is not discarded. After authenticated exit, surviving windows return to their original workspaces and the previously focused window is focused again. Pinned windows are temporarily unpinned and regain their pinned state on exit. A best-effort launch guard keeps a pre-existing single-instance app hidden if starting it from the Kids menu would otherwise reveal the parent's existing window.

Any installed desktop app can be added to or removed from the allowlist. Use the **All**, **Selected**, and **Not Selected** quick filters to review the current allowlist or find apps that can still be added. Their keyboard shortcuts are `Ctrl+1`, `Ctrl+2`, and `Ctrl+3`; `Ctrl+Shift+K` activates the mode switch. The selection and mode are saved to:

```text
~/.config/omarchy-kids/allowed-apps.json
~/.config/omarchy-kids/mode.json
~/.local/state/omarchy-kids/windows.json
```

When Kids Mode first enables Do Not Disturb, it remembers the existing notification preference in `~/.local/state/omarchy-kids/notifications.json`. Turning Kids Mode off or disabling the plugin restores that preference. Omarchy action confirmations and trusted critical command-line alerts retain the operating system's normal DND bypass behavior.

## Install

Publish or clone this directory as its own Git repository, then run:

```bash
omarchy plugin add https://example.com/omarchy-kids-menu.git --enable
```

For local development, copy the directory to `~/.config/omarchy/plugins/omarchy-kids.menu`, then run:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/omarchy-kids.menu
omarchy-shell shell rescanPlugins
omarchy plugin enable omarchy-kids.menu
```

For normal use, switch modes from the right-side Kids Mode manager. These commands control installation-level plugin activation and are retained for maintenance:

```bash
omarchy plugin disable omarchy-kids.menu
omarchy plugin enable omarchy-kids.menu
```

## Scope

The plugin filters the Omarchy menu, stores desktop-entry IDs and its mode in its own config, launches Chromium with a separate user-owned profile while Kids Mode is on, temporarily moves existing windows without closing them, temporarily controls Omarchy's Do Not Disturb state, keeps the standard menu symbol on the left, and manages a separate right-side bar control. It removes the menu button's right-click terminal shortcut. It does not install or remove applications, rewrite Hyprland keybindings, restrict terminal commands, filter the web, or prevent a knowledgeable user from disabling the plugin or reaching the hidden workspace through another route. Authentication protects the in-app Exit action; it is not a system security boundary.

## Testing

Run the static checks on an Omarchy host with:

```bash
./test/run
```

`test/vm-acceptance` is intended for a disposable VM installed from an official Omarchy ISO. It verifies presence-sensitive defaults, notification suppression and restoration, adds an installed app through the persisted allowlist, checks blocked stock routes, confirms the package set is unchanged, and verifies installation-level disable/restore. Set `OMARCHY_KIDS_TEST_PASSWORD` only in a disposable guest to add the wrong-password, valid-password, internal Off, normal-menu, and immediate-On checks.
