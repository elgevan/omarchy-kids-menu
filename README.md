# Kids Mode for Omarchy

Kids Mode gives a child a simple Omarchy desktop with access to only the apps you choose.

When Kids Mode starts, it:

- Hides the parent's open apps without closing them.
- Shows only approved apps in the Omarchy menu.
- Uses a separate Chromium profile for the child.
- Filters shortcuts that would open unapproved apps or settings.
- Turns on Do Not Disturb.

Exiting Kids Mode requires the account password or a configured fingerprint. The parent's apps, workspaces, shortcuts, and notification settings are then restored.

## Requirements

- Omarchy 4 with the Quattro shell
- Chromium installed at `/usr/bin/chromium`

## Install

```bash
omarchy plugin add https://github.com/elgevan/omarchy-kids-menu.git --enable
```

After installation, click the child icon on the right side of the bar to open the Kids Mode manager.

## Use

1. Open the Kids Mode manager.
2. Select the apps the child can use.
3. Click **Start Kids Mode**.

The normal Omarchy button now opens the approved app list. The default selections are Google Chrome, Chromium, Omawrite, and Omacalc when those apps are installed.

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
