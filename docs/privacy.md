# Privacy and local data

Stint has no account system, app backend, advertising SDK, or app analytics service. Timer and progress data stay on your Mac. This describes Stint's code; third-party services such as YouTube have their own policies.

## What is stored

The workspace stores your current timer, interval settings, saved rhythms, daily goal, appearance, and completed focus sessions. The native preferences store music settings, alert selection, and keyboard shortcuts. Imported audio is copied into a local music library. Saved YouTube sources contain a video ID and the name you provided.

Stint retains the earlier `com.focusdesk.focusDesk` bundle identity and `Focus Desk` Application Support directory for compatibility. macOS decides the actual Application Support location; a sandboxed app may use its container. The workspace uses a temporary file, an atomic replacement, and a previous valid backup. Unreadable files are retained for recovery instead of silently overwritten.

Older workspace files may still contain task and note records from the earlier prototype. Those features are no longer exposed in the interface, but migration preserves their data. Review backups before sharing them.

## Network behavior

Built-in and imported audio play locally. YouTube playback loads the official IFrame player through WebKit and needs an internet connection. YouTube may receive the normal information associated with an embedded video request. Stint does not download the video's audio. The player appears inside the menu bar timer panel and pauses when the panel hides.

Flutter tooling, package downloads, and the optional video editor may access the network during development. Those build tools are separate from the running Stint app.

## Keyboard shortcuts

Mac-wide mode registers only the configured hotkeys. Stint does not install a global keyboard event tap to collect unrelated typing. Recording uses an app-local key event monitor while the shortcut editor explicitly requests a binding. Escape or switching away from Stint cancels recording.

## Notifications

Stint uses native macOS notifications and its own completion card. The OS controls notification permissions, Focus filtering, and Notification Center history. Timer alert audio plays separately while Stint is running. See [troubleshooting](troubleshooting.md) if a banner or sound is missing.

## Sharing diagnostics

Prefer screenshots made with demonstration data and a small reproduction. Do not attach your entire Application Support folder, imported music, or workspace backup to an issue. Before sharing logs, check for file paths, source names, URLs, and personal content.

## Removing data

Quit Stint before managing its saved data. Back up the app's resolved Application Support directory first if you want to keep your history or imported files. Deleting the app bundle alone may leave its container and preferences behind. Stint does not yet provide an in-app erase-all-data action.
