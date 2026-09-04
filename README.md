# Omarchy Kid Menu

Omarchy Kid Menu makes it easier to share the Omarchy desktop you already use with a child. It does not create another Linux user or a separate desktop profile. Browser apps open in a separate Chromium profile, so the child does not see your regular browser history, bookmarks, or signed-in sites such as YouTube.

When you start **Kids Mode**, your apps stay open but move out of view. The child sees only the apps you choose. Kids Mode also simplifies the bar, pauses shortcuts that open other apps or settings, and turns on Do Not Disturb.

When you leave Kids Mode, Omarchy asks for your password or fingerprint and restores your desktop as it was.

This is meant for supervised use on a shared account. It helps prevent accidental access, but it is not a replacement for a separate user account, website filtering, or parental controls.

## Install

You need Omarchy 4 with the Quattro shell and Chromium installed.

```bash
omarchy plugin add https://github.com/elgevan/omarchy-kids-menu.git --enable
```

The plugin uses Omarchy's normal lock and notification services, along with the standard `hyprctl`, `jq`, `flock`, Coreutils, and `uwsm-app` tools. It does not need `sudo` or `pkexec`, install packages, or download code.

## Use

1. Click the Kids Mode icon on the right side of the bar.
2. Choose which apps the child can open.
3. Click **Start Kids Mode**.

The Omarchy button now opens the chosen app list. Numbered workspace shortcuts still work, but shortcuts that open other apps or desktop settings are paused. You cannot change the app list until you leave Kids Mode.

To return to your desktop, open the Kids Mode panel and click **Exit Kids Mode**. After you unlock the screen, Kids Mode closes its apps and restores your windows, workspaces, shortcuts, menu, bar, and notification setting.

If an app asks for confirmation before closing, Kids Mode stays active so you can answer it safely. The password check protects the exit button, but software running as the same Linux user can still change the plugin's files or turn it off.

## Chromium profile

Chromium, Google Chrome, and supported web apps use one separate browser profile while Kids Mode is active. Its bookmarks, history, extensions, settings, and sign-ins stay between sessions without mixing with your normal browser profile.

The profile is shared by Kids Mode, not created separately for each child. It is stored at:

```text
~/.local/share/omarchy-kids/chromium
```

Kids Mode does not filter websites.

## Remove

```bash
omarchy plugin remove io.github.elgevan.omarchy-kids
```

Removing the plugin restores the normal desktop. Your chosen app list and Kids Mode browser profile are kept in case you install it again.

If a Kids Mode app refuses to close, answer its prompt and try removing the plugin again. Signing out also closes any remaining session windows.

## Test

```bash
./test/run
```

`test/vm-acceptance` runs the complete flow in a disposable Omarchy VM.
