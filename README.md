# Omarchy Kids Menu

This proof-of-concept Omarchy plugin replaces the stock `omarchy.menu` while enabled. Its root shows only installed desktop applications selected in the plugin plus Omarchy's Style menu when the style tools are available. It is a convenience filter, not a security boundary.

The plugin uses Omarchy's `omarchy.clonedFrom` contract, so existing menu keybindings and IPC calls continue targeting `omarchy.menu`. Disabling the plugin restores the stock menu automatically.

There is no Apps submenu. The plugin redirects Omarchy's stock Apps-menu shortcut (`Super+Alt+Space`) and blocked stock routes to the flattened kids root.

The initial allowlist is Google Chrome, Chromium, Omawrite, and Omacalc. These are desktop-entry IDs, not launch commands: a default app appears only when it is installed. Style follows the same rule and is omitted when Omarchy's style commands are unavailable.

The normal Omarchy symbol stays in its usual place on the left and opens the filtered menu. A separate child icon is installed with the other plugins on the right; click it to open **Kids Menu Apps**, where any installed desktop app can be added to or removed from the allowlist. The selection is saved to:

```text
~/.config/omarchy-kids/allowed-apps.json
```

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

Switch between the two menus with:

```bash
omarchy plugin disable omarchy-kids.menu
omarchy plugin enable omarchy-kids.menu
```

## Scope

The plugin filters the Omarchy menu, stores only desktop-entry IDs in its own config, keeps the standard menu symbol on the left, and manages a separate right-side bar control. It removes the menu button's right-click terminal shortcut. It does not install or remove applications, rewrite Hyprland keybindings, restrict terminal commands, filter the web, or prevent the user from disabling the plugin.

## Testing

Run the static checks on an Omarchy host with:

```bash
./test/run
```

`test/vm-acceptance` is intended for a disposable VM installed from an official Omarchy ISO. It verifies presence-sensitive defaults, adds an installed app through the persisted allowlist, checks blocked stock routes, confirms the package set is unchanged, disables the plugin, and verifies that the stock menu returns.
