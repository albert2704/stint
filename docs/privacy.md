# Privacy and local data

The Stint macOS app has no account system, hosted app backend, advertising SDK, or app analytics service. Timer and progress data stay on your Mac. The public website is described separately below; third-party hosting, download, and playback services have their own policies.

## Public website

The [Stint website](https://stint-focus.vercel.app/) is a static feature tour and download page hosted on Vercel. Its fonts are served with the site. Its current code does not include an analytics client, account form, or connection to your Mac's workspace.

The site starts with your system appearance. If you choose light or dark using its header toggle, it saves only that choice in your browser's `localStorage`, under `stint-theme`. This preference is separate from the Mac app's appearance setting. Clearing the site's browser data removes the saved choice.

The animated countdown is an illustration. It does not run or record your focus sessions, play music, or read your app history. Visiting the site sends normal web requests to its hosting provider; following download and source links sends requests to GitHub. These services operate independently of the app's local storage.

## What is stored

The workspace stores your current timer, interval settings, saved rhythms, daily goal, appearance, and completed focus sessions. The native preferences store music settings, alert selection, and keyboard shortcuts. Imported audio is copied into a local music library. Saved YouTube sources contain a video ID and the name you provided.

Version 0.3.0 also stores Flow checkpoints, a weekly target and the optional Pick up here sentence in the workspace. Completed sessions can retain that sentence as it was at completion. `focus-profiles.json` stores named snapshots of timer, music, ambient levels and blocker settings. Ambient preferences and original bundled loops remain local. These features add no analytics or cloud service.

Version 0.2.0 beta adds `blocker.json` for the enabled setting, selected app names and bundle identifiers, website domains, and current-stint override. It is separate from `workspace.json` and its previous-save backup. Stint does not store visited URLs. Stint does not encrypt local files itself.

Version 0.1.1 uses the `io.github.albert2704.stint` bundle identity, `Stint` Application Support directory, and Stint native preference keys. It starts with fresh settings, history, music library, and permissions when you upgrade from 0.1.0. The previous data is left untouched and is not read or imported automatically.

macOS decides the actual Application Support location; a sandboxed app may use its container. The workspace uses a temporary file, an atomic replacement, and a previous valid backup. Unreadable files are retained for recovery instead of silently overwritten.

The workspace schema can still contain task and note records, although those features are no longer exposed in the interface. Keeping those record types compatible does not migrate data from the earlier app identity. Review backups before sharing them.

## Network behavior

Built-in and imported audio play locally. YouTube playback loads the official IFrame player through WebKit and needs an internet connection. YouTube may receive the normal information associated with an embedded video request. Stint does not download the video's audio. The player appears inside the menu bar timer panel and pauses when the panel hides.

The optional website blocker runs a local proxy bound only to 127.0.0.1:48197 inside Stint. The helper temporarily selects it in macOS network settings during focus. It reads destination hostnames and plain HTTP request headers in memory to forward or refuse connections. HTTPS payloads remain encrypted. It does not query browser tabs or send your blocklist or browsing activity to a cloud service.

Flutter tooling, package downloads, and the optional video editor may access the network during development. Those build tools are separate from the running Stint app.

## App and website blocking

This feature is included in version 0.2.0 beta; the earlier 0.1.1 package does not include it. See [setup and behavior](blocking.md).

App blocking observes which application becomes active and compares its bundle identifier with your saved list. It attempts to hide a selected app without terminating it or reading its documents. It does not request Accessibility access or install a keyboard event tap.

Website protection uses a small root helper installed only after you approve the bundled Terminal setup with your own administrator password. Stint does not collect that password. No paid network extension, browser extension or Automation access is used.

The app writes normalized domains, focus session identifier, user ID, issue time, deadline and a short lease to `~/Library/Application Support/Stint Website Blocker/policy.json`. A narrowly scoped sandbox exception permits access to that directory. The helper reads only a regular file owned by the configured user, validates it, and writes a root-owned status file there. The status contains health and timing information, not domains or browsing history. The root configuration stores the installing user ID.

The proxy keeps only in memory connection state and has no browsing, payload or DNS query logs. The helper keeps original proxy values in a root owned recovery journal, including previous server and port settings, until restoration succeeds. Policy version 2 includes a per launch token for local server health checks. Invalid or missing policies release routing while the helper is running. Old Stint hosts entries are removed during upgrade, and new focus sessions no longer write the hosts file.

Proxy settings affect all users of the network services, including Stint’s YouTube music. Apps that ignore system proxies are outside protection. Removing the app bundle alone does not uninstall the LaunchDaemon. Use [Remove helper or recovery](blocking.md#remove-or-recover-the-helper) before deleting the app. Removing the helper leaves your user-owned policy/status folder and saved app data; delete those separately if desired after the helper is removed.

## Keyboard shortcuts

Mac-wide mode registers only the configured hotkeys. Stint does not install a global keyboard event tap to collect unrelated typing. Recording uses an app-local key event monitor while the shortcut editor explicitly requests a binding. Escape or switching away from Stint cancels recording.

## Notifications

Stint uses native macOS notifications and its own completion card. The OS controls notification permissions, Focus filtering, and Notification Center history. Timer alert audio plays separately while Stint is running. See [troubleshooting](troubleshooting.md) if a banner or sound is missing.

## Sharing diagnostics

Prefer screenshots made with demonstration data and a small reproduction. Do not attach your entire Application Support folder, imported music, workspace backup, private blocklist or any old `browser-pairing.json` to an issue. Before sharing logs, check for file paths, source names, URLs, blocklist entries and personal content.

## Removing data

Quit Stint before managing its saved data. Back up the app's resolved Application Support directory first if you want to keep your history or imported files. Deleting the app bundle alone may leave its container and preferences behind. Stint does not yet provide an in-app erase-all-data action.

If you used the earlier extension preview, remove that extension manually from each browser/profile and delete its exported folder if you no longer need it. The current app does not read or write the old `browser-pairing.json`; its owner can delete that obsolete file from the resolved Stint data directory. Updating the app does not remove these files, exported folders or browser installations automatically, and it preserves `blocker.json` and your other saved data.
