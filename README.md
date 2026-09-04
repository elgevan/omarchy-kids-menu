# Omarchy Kids Mode

Omarchy Kids Mode makes it easier to share the Omarchy desktop you already use with a child. It does not create another Linux user or a separate desktop profile. Chromium, Google Chrome, and supported Omarchy web apps launch in a separate Chromium profile, keeping that browsing separate from your regular history, bookmarks, and signed-in sites such as YouTube.

When you start **Kids Mode**, your apps stay open but move out of view. The child starts on workspace 1 and sees only the apps you choose. Kids Mode also hides other visible shell plugins, simplifies the bar, pauses shortcuts that open other apps or settings, and turns on Do Not Disturb.

New windows begin in a private quarantine while Kids Mode is active. Windows launched from selected apps through Kids Mode are admitted to the child's current workspace; unexpected windows and dialogs from the adult session remain hidden.

When you leave Kids Mode, Omarchy asks for your password or fingerprint and restores your desktop as it was.

This is meant for supervised use on a shared account. It helps prevent accidental access, but it is not a replacement for a separate user account, website filtering, or parental controls.

## Install

You need Omarchy 4 with the Quattro shell and Chromium installed.

Enabling the plugin replaces the stock menu widget with its Kids Mode counterpart and adds a Kids Mode button on the right side of the bar. The menu keeps its normal behavior until you start Kids Mode. Disabling or removing the plugin restores the original menu placement.

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

If a protection cannot be maintained or the saved mode state cannot be verified, Kids Mode keeps the adult desktop hidden and locks the screen. Restoring the desktop from that state requires another successful password or fingerprint check.

## Chromium profile

Chromium, Google Chrome, and supported Omarchy web apps launch through Chromium with one separate browser profile while Kids Mode is active. Supported web apps are shortcuts that use `omarchy-launch-webapp` with an HTTP or HTTPS URL. The profile's bookmarks, history, extensions, settings, and sign-ins stay between sessions without mixing with your normal browser profile.

Other browsers, including Firefox, and other selected applications use their normal launch behavior and retain access to their usual profiles and account data. Only select apps whose existing data you are comfortable sharing.

The profile is shared by Kids Mode, not created separately for each child. It is stored at:

```text
~/.local/share/omarchy-kids/chromium
```

Kids Mode does not filter websites.

## Remove

First exit Kids Mode and wait for your desktop to be restored. If an app asks for confirmation before closing, answer its prompt and retry **Exit Kids Mode**. Then remove the plugin:

```bash
omarchy plugin remove io.github.elgevan.omarchy-kids
```

Your chosen app list and Kids Mode browser profile are kept in case you install it again.

If you remove the plugin while Kids Mode is active, desktop cleanup retries in the background after removal. If cleanup cannot finish, shortcut restrictions are released but some windows may remain hidden. Sign out and back in to recover the session; running the removal command again cannot retry cleanup for an already-removed plugin.

## Test

```bash
./test/run
```

`test/vm-acceptance` runs the complete flow in a disposable Omarchy VM.
