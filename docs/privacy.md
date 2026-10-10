# Privacy and local data

The Stint macOS app has no account system, app backend, advertising SDK, or app analytics service. Timer and progress data stay on your Mac. The public website is described separately below; third-party hosting, download, and playback services have their own policies.

## Public website

The [Stint website](https://stint-focus.vercel.app/) is a static feature tour and download page hosted on Vercel. Its fonts are served with the site. Its current code does not include an analytics client, account form, or connection to your Mac's workspace.

The site starts with your system appearance. If you choose light or dark using its header toggle, it saves only that choice in your browser's `localStorage`, under `stint-theme`. This preference is separate from the Mac app's appearance setting. Clearing the site's browser data removes the saved choice.

The animated countdown is an illustration. It does not run or record your focus sessions, play music, or read your app history. Visiting the site sends normal web requests to its hosting provider; following download and source links sends requests to GitHub. These services operate independently of the app's local storage.

## What is stored

The workspace stores your current timer, interval settings, saved rhythms, daily goal, appearance, and completed focus sessions. The native preferences store music settings, alert selection, and keyboard shortcuts. Imported audio is copied into a local music library. Saved YouTube sources contain a video ID and the name you provided.

Version 0.1.1 uses the `io.github.albert2704.stint` bundle identity, `Stint` Application Support directory, and Stint native preference keys. It starts with fresh settings, history, music library, and permissions when you upgrade from 0.1.0. The previous data is left untouched and is not read or imported automatically.

macOS decides the actual Application Support location; a sandboxed app may use its container. The workspace uses a temporary file, an atomic replacement, and a previous valid backup. Unreadable files are retained for recovery instead of silently overwritten.

The workspace schema can still contain task and note records, although those features are no longer exposed in the interface. Keeping those record types compatible does not migrate data from the earlier app identity. Review backups before sharing them.

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
