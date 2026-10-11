# Troubleshooting Stint

[User guide](user-guide.md) · [Build instructions](development.md) · [Contributing](../CONTRIBUTING.md)

## The main window closed, but the timer is still running

This is expected. Closing the window keeps Stint in the menu bar. Click its countdown for controls and choose **Open Stint** to reopen the window. **Stint → Quit Stint** exits the app. Use Pause before quitting if you do not want the saved interval to continue toward its deadline.

## I changed a duration, but the countdown did not change

**Save settings** changes durations for future intervals. It preserves the current interval, including an idle one. Use the current timer's **− / +** buttons to change only that countdown. Applying a rhythm explicitly prepares a focus interval and asks before discarding unfinished time.

The minus button will not reduce the timer below a minute. Once fewer than 60 seconds remain, it leaves that remaining time alone.

## I cannot hear the completion alert

1. Choose **Stint → Test alert sound**. It should play the selected sound twice.
2. Check macOS output volume, mute, and the selected output device. Stint's music slider does not control alert volume.
3. Open Settings, preview another alert such as **Ping**, then use **Save settings** if you want to keep it.
4. Distinguish the two paths: a running Stint plays its direct chime; an alert after normal Quit uses macOS notifications.

If the direct test works but a live interval does not alert, report whether the app stayed running, the Mac slept, or you quit it. Include the phase and whether the next interval appeared. A **Preview notification** is deliberately silent and is not an audio test.

For the after-Quit path, allow Stint in **System Settings → Notifications**, enable the desired sound/banner presentation, and inspect Focus settings. That path depends on macOS scheduling and presentation. Force Quit does not run the normal termination handoff. Actual after-Quit audible delivery is still a live-verification limit of this version.

## The notification does not look like the Stint card

The branded card is shown by the running app. Notification Center keeps a quiet system record while Stint runs; after normal Quit, macOS presents the scheduled system notification using its own appearance.

Use **Stint → Preview notification** to inspect the card. Its buttons dismiss the preview without changing the timer. A real completion card temporarily hides while the menu bar panel is open and disappears when the timer advances or you dismiss it.

## Music does not start with the timer

Turn on **Play with timer**, select a source, then start or resume the timer. The option covers focus and both break types.

Some pauses are intentional:

- Launching Stint restores the timer but keeps music silent.
- Selecting a different track stops playback; press Play or make a new timer transition to start it.
- A manual music pause is respected until the next timer transition.
- Closing or hiding the YouTube panel pauses its player while the timer continues.
- Turning Play with timer off leaves playback under manual control.

Try a built-in track with the music volume raised. If it works, the issue is specific to the import or YouTube source. If an error is shown, include its exact text in a report.

## An audio file will not import or play

Choose a nonempty file no larger than 200 MB. Try a normal MP3, M4A, WAV, or AIFF file that macOS can decode. A misleading filename extension does not make an unsupported encoding playable.

Stint validates all files in one picker selection before adding that selection to the library. If one fails, retry the working files separately. Ensure the app can read the selected file and that there is room for an additional copy in local storage.

An imported file is a separate app-owned copy. Moving the original is safe, but manually deleting files from Stint's music folder can make the saved source unavailable. Import the file again through **Add → Audio file**. Removing it from the Stint UI deletes only the app's copy.

## YouTube does not play

Confirm the link identifies one video or live stream, not just a channel or playlist. Stint accepts common `youtube.com/watch`, `youtu.be`, `shorts`, `live`, and `embed` video links. It stores the video ID, not all URL options.

Open **Show player**, keep the menu bar panel visible, and press **Play**. Reopening the panel is not itself a playback command. Check your connection and wait for loading to complete. On an autoplay-blocked message, use the visible player controls.

Some videos disallow embedding, require account/age access, are region-restricted, or have ended. Try another publicly embeddable video. WebKit or YouTube policy changes can affect real playback even when the app's native harness passes. Stint does not offer background audio extraction or offline YouTube downloads.

If playback works once but not after hiding and reopening, report that exact sequence. Include whether Stint showed **Playing**, **Starting**, or an error, and whether the player was visible. Do not publish private/unlisted links without permission.

## Shortcuts do not trigger

1. Confirm Stint is running; closing its window is fine, quitting is not.
2. Open **Settings → Keyboard shortcuts** and inspect the saved scope. **Only in Stint** cannot control the app from Finder or another foreground app.
3. Save the editor with **Save shortcuts**. Saving or cancelling the parent Settings sheet does not replace this separate save step.
4. Make sure the action is not cleared. Try **Restore defaults**, then Save shortcuts, or choose another combination if a conflict is reported.
5. End shortcut recording before testing actions. Escape cancels recording, and changing apps cancels it too.

Default shortcuts hold **Control + Option + Command**, with **P** for Start/Pause, **R** for Reset, **N** for Skip, and **S** for the timer panel. Reset and Skip may show a confirmation instead of immediately changing the interval.

Custom combinations need Control or Command. Common system/app chords are reserved. Bindings use physical key positions with US-position labels, so a non-US keyboard layout can display a different character from the label. Function keys may also depend on your keyboard's function-key mode.

Registration and dispatch have native automated coverage, but physical global key delivery has not yet been verified across devices. If a chord saves successfully but does nothing from another app, report macOS version, keyboard layout, scope, chord, and whether **Only in Stint** works. Do not grant unrelated accessibility or keyboard-monitoring permissions as a workaround; Stint currently has no such permission flow.

## Progress looks different from what I expected

Only focus intervals that reach completion add stints. A pause, reset, skip, or cycle jump does not. A completed focus interval is attributed to the local date of its deadline, not the date on which you next open the app.

The streak counts consecutive days with at least one stint. The daily goal is a separate measure. Historical goal days use your current goal, so raising or lowering the goal can change the weekly goal-day count. Changing timezone can move a saved completion to a different local day. Week boundaries follow the app locale.

If a saved goal reports an error, keep Progress open and use **Retry save**. Do not infer that an onscreen edit is durable while a save error remains.

## Distraction blocking is not working

First check your build. The blocker is included in [0.2.0 beta](https://github.com/albert2704/stint/releases/tag/v0.2.0-beta.1); the older 0.1.1 download does not include it. Install the beta or [build the current source](development.md), then follow the [setup guide](blocking.md).

In **Block distractions**, turn on **Block during focus**, choose apps or websites, and use **Save blocklist**. Blocking runs only during an unexpired focus timer. It deliberately releases on pause, breaks, reset, skip or completion. If you chose **Unblock this stint**, it stays released through pause/resume of that interval and returns for the next focus interval. Closing the main window keeps Stint running; quitting it stops protection.

For websites:

1. **Setup needed** means no recent root-owned helper status is available. Choose **Set up website blocker**, double-click the command revealed in Finder, read its Terminal explanation and complete administrator approval yourself, then refresh. No Apple subscription is needed.
2. **Helper ready** reports recent helper health; its message distinguishes active blocking from idle. Check that a focus timer is running, the feature is enabled and your saved list is nonempty.
3. Each domain covers its subdomains. Enter a normal domain, without a wildcard. An existing custom proxy or unsupported exception list prevents activation and is reported without being overwritten.
4. Cached pages and buffered video can remain visible. Apps that ignore macOS proxy settings are outside protection. Test a fresh navigation and reload after release.
5. Proxy settings affect all accounts using the network services. If YouTube music fails while YouTube is blocked, select built-in or local music.

App hiding works independently. Choose an actual app bundle; Stint, browsers and recovery utilities are protected. Apps that refuse to hide report an error and remain running.

### YouTube still opens during focus

Check Block distractions: the new proxy needs the updated helper installed and a running focus session. A helper from the earlier hosts preview is deliberately shown as needing an upgrade. Choose Set up website blocker, open the highlighted command in Finder, finish its administrator prompts, then Refresh.

Use a fresh navigation or reload to test access. Loaded pages and buffered video can remain visible. Chrome and Edge must use macOS proxy settings; custom proxies, VPNs and apps that ignore those settings are unsupported. Stint refuses existing enabled proxies rather than overwriting them. If the status reports a conflict, resolve it and start a new focus.

The previous hosts implementation let an existing Edge session load YouTube even when macOS and Edge resolved it to loopback; a fresh InPrivate session failed. That observation motivated this proxy replacement. Do not treat a DNS lookup alone as proof of browser blocking.

If allowed websites stop loading after Stint exits, use the [proxy recovery steps](blocking.md#remove-or-recover-the-helper). Disable only Stint's 127.0.0.1:48197 HTTP/HTTPS settings if the helper cannot restore them.

## Stint cannot load or save data

For a save error, keep the app open and retry after checking free disk space and access to its local data. Timer actions can update the onscreen state even if writing it fails; quitting before a successful save may lose those changes.

If startup cannot decode the workspace, it shows the error and the resolved data location. Use **Try again** for a temporary problem. If a valid backup exists, **Recover previous save** loads the preceding saved workspace. That may roll back the most recent timer/settings/history change; it is not a complete backup history.

Before manual recovery, quit Stint and make a copy of the complete resolved **Stint** data folder and its native preferences. The workspace JSON alone does not contain imported audio, music selections, shortcut settings, or WebKit data. Preserve `workspace.backup.json` and any `workspace.json.damaged-*` files. Do not delete them merely to make an error disappear.

Data is stored in macOS's Application Support location for this app, potentially inside its sandbox container. Version 0.1.1 uses the **Stint** folder and `io.github.albert2704.stint` identity. See [persistence details](architecture.md#persistence-and-compatibility).

## My settings or history disappeared after updating to 0.1.1

Version 0.1.1 deliberately starts fresh with a new application identity. It does not read or import 0.1.0 settings, history, music library, shortcuts, or permissions. Your previous data was not deleted; it remains under the previous app identity. The new app has no automatic migration or import action for that workspace.

Quit the old app before running the new one, then choose your rhythm and music again and allow notifications when prompted. The current app's **Recover previous save** only restores a backup from its own workspace. It does not retrieve the previous app's data.

## Build or test failures

| Symptom | What to check |
| --- | --- |
| “Install Flutter and add it to PATH” | Install Flutter, or provide `.tooling/flutter/bin/flutter`. Confirm `bash scripts/flutter.sh --version` works. |
| `xcrun` cannot locate the macOS SDK | Install/configure Command Line Tools or full Xcode, then check `xcode-select -p` and `xcrun --sdk macosx --show-sdk-path`. |
| Local helper rejects the architecture | The debug helper targets Apple Silicon. The separate full Xcode package includes both architectures and passed 0.2.0 beta package checks; physical Intel testing remains unverified. |
| Flutter framework missing for a native test | Run the development build or macOS precache first, and check which SDK the scripts resolve. |
| First build fails while fetching dependencies | Check network access and retry. Dependencies and engine artifacts are needed before an offline build. |
| Missing native channel / plugin response | Use one of the supplied Mac hosts. A generic Flutter host or another platform does not provide these services. |
| App UI does not include recent code | Quit the old bundle, rebuild, then open the exact newly built path. Avoid running local and verified copies together. |
| macOS warns about a downloaded build | The prerelease has an ad hoc signature, without Apple Developer ID signing or notarization. Read the [installation guide](install.md#first-launch-and-gatekeeper) and Apple's guidance before deciding whether you trust it. |

The Command Line Tools helper and standard Xcode runner are different hosts. A successful local helper build does not establish a successful Xcode release build. See [development](development.md) for the supported commands and limits.

## Packaging a download fails

`scripts/package-macos.sh` needs full Xcode. If it reports that Xcode is missing, install/configure full Xcode or use the manual **Package macOS** GitHub workflow. The Apple Silicon debug helper is a separate development route and does not create universal release archives.

The package script deliberately fails when it cannot verify the expected architecture slices, release entitlements, app version, signature, or disk image. Keep the failure and build log when reporting a problem; do not upload a partially generated archive as a release.

The release bootstrap script runs only on a disposable GitHub runner. A refusal on your Mac is intentional. It checks the app's startup and sandbox data directory without using your existing profile. Do not bypass its environment checks.

GitHub workflow artifacts expire after 14 days and are separate from permanent release assets. If a completed run's artifact has expired, rerun the workflow against the intended commit. A published prerelease should expose its DMG, ZIP, and checksum file on the versioned release page.

## Useful information in a bug report

Include the Stint version/commit, macOS version, Apple Silicon or Intel, build route, exact reproduction steps, expected and actual behavior, and the relevant error text. For visual bugs, add a screenshot or short recording with personal filenames, links, and other apps cropped out.

The local executable's `--notification-status` option can help with notification issues; see [diagnostics](development.md#useful-diagnostics). Review any output before sharing it. Do not attach your workspace, preferences, private audio, or full system logs by default.
