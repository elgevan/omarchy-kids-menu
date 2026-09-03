# Omarchy Kids Menu

This proof-of-concept Omarchy plugin replaces the stock `omarchy.menu` while enabled. It elevates a static allowlist of applications directly into the root menu alongside Style and System. It is a convenience filter, not a security boundary.

The plugin uses Omarchy's `omarchy.clonedFrom` contract, so existing menu keybindings and IPC calls continue targeting `omarchy.menu`. Disabling the plugin restores the stock menu automatically.

There is no visible Apps submenu. A hidden compatibility route makes Omarchy's stock Apps-menu shortcut (`Super+Alt+Space`) open the flattened root menu.

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

An optional guardian-managed extension can be placed at `~/.config/omarchy-kids/menu.jsonc`. It is merged only with the kids menu; the normal Omarchy user-menu extension is intentionally not loaded while this plugin is active.

## Scope

The plugin filters the Omarchy menu and removes the menu button's right-click terminal shortcut. It does not remove installed applications, rewrite Hyprland keybindings, restrict terminal commands, filter the web, or prevent the user from disabling the plugin.

## Testing

Run the static checks on an Omarchy host with:

```bash
./test/run
```

`test/vm-acceptance` is intended for a disposable VM installed from an official Omarchy ISO. It installs this repository through `omarchy plugin add`, captures the flattened root and filtered System menus, checks the legacy Apps route, disables the plugin, and verifies that the stock menu returns.
