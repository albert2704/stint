# Using Stint

Stint is a Mac Pomodoro timer with a menu bar countdown, focus music, and a record of completed focus sessions. A **stint** is one completed focus interval. The current app is for macOS; Android is not implemented.

[Build and run Stint](development.md) · [Troubleshooting](troubleshooting.md) · [Back to the README](../README.md)

## Your first stint

1. Open Stint and choose **Rhythms**.
2. Choose a rhythm that suits the session. **Classic** gives you 25 minutes of focus, a 5-minute short break, and a 15-minute long break.
3. Optionally choose a track under **Sound**. Turn on **Play with timer** to start and pause music with the countdown.
4. Press **Start**. You can close the window and keep the countdown in the macOS menu bar.
5. When the interval ends, the alert plays twice. Use the completion card to start the offered break when you are ready.

The next interval is prepared, but does not start automatically. After a break, start the next focus stint in the same way.

## Timer controls

### Flow mode

Choose **Flow** near the timer to count upward from zero. Pause and Resume preserve focused time. **Take break** records the elapsed focus once and prepares the next break, which waits for you to start it. The suggested break is one fifth of focus time, rounded up to a whole minute and bounded to 1–30 minutes. The fourth stint still leads to the long break position. After a break, the next focus uses Flow again.

Switching mode with unfinished time asks for confirmation. Flow does not schedule an end alert while counting upward. It requests a pause when the Mac sleeps. After relaunch it restores paused from the latest saved checkpoint, without counting time while Stint was closed. Checkpoints save every 15 running seconds, so quitting or a crash can lose up to 15 seconds. Pause before quitting to save the exact elapsed time. Pomodoro keeps its existing deadline recovery.

### Pick up here

Use **Pick up here** to save a short next step, such as “Next: fix the login redirect.” The sentence is optional, limited to 240 characters and kept until you edit or clear it. You can also open its editor from the menu bar panel.

### Focus profiles

Open **Profiles** to choose Coding, Writing or Study, or save your current setup with a name. A profile saves timer mode and durations, selected music and volume, Play with timer, ambient levels, and the blocker list and enabled setting.

Configure the app as you like, then choose **Save current setup…**. A profile's options let you update it from your current setup, rename it or delete it. Applying a profile prepares an idle focus interval. It never starts audio or installs a website helper. An unfinished interval requires confirmation before any settings change. If a saved imported track is missing, Stint uses Quiet Keys and explains the fallback.

These additions are included in [0.3.0 beta](https://github.com/albert2704/stint/releases/tag/v0.3.0-beta.1).

The main window and menu bar panel control the same timer. Click the countdown in the menu bar to open the compact panel; use **Open Stint** to return to the main window.

| Control | What it does |
| --- | --- |
| Start / Resume | Runs the current interval from its remaining time. |
| Pause | Stops the countdown and keeps the remaining time. |
| Reset | Prepares the current cycle position again using the saved duration. |
| Skip | Prepares the next position in the cycle. It does not record a completed stint. |
| − / + | Removes or adds one minute to this interval only. It does not change the saved rhythm. |
| Cycle segment | Jumps to that focus or break position, without adding a completion. |

Reset, Skip, jumping to another segment, and applying a different rhythm ask for confirmation if the interval has started. The inline confirmation is shared by both timer surfaces. **Cancel** keeps the current interval. A running countdown continues while the confirmation is visible.

The cycle contains eight positions:

```text
Focus → Short break → Focus → Short break → Focus → Short break → Focus → Long break
  ↑_______________________________________________________________________________|
```

The fourth focus position leads to a long break. You can move around the cycle manually; the cycle position and your saved completion history are separate.

Minute adjustment has a one-minute remaining-time floor. Focus is capped at 120 minutes remaining and breaks at 60. If the countdown is already below a minute, the minus button does not extend it back to a minute.

Closing the window keeps Stint running. Choose **Stint → Quit Stint** to exit. For Pomodoro focus and timed breaks, the saved deadline lets Stint settle a running interval on its next launch, including an interval that expired while the app was closed. It prepares one next interval instead of inventing unattended cycles. Flow focus restores paused from its last saved checkpoint.

## Rhythms and settings

| Built-in rhythm | Focus | Short break | Long break |
| --- | ---: | ---: | ---: |
| Quick focus | 15 min | 3 min | 15 min |
| Classic | 25 min | 5 min | 15 min |
| Deep work | 50 min | 10 min | 30 min |

Applying a rhythm from the Rhythms menu prepares an idle focus interval at the current focus position, or the next focus position if you are on a break. Existing completed stints stay in Progress.

In **Settings**, adjust the three durations and use **Save these durations** to create a named custom rhythm. Focus accepts 1–120 minutes; either break accepts 1–60 minutes. Custom rhythm names can contain up to 80 characters. You can delete custom rhythms; built-in rhythms remain available.

Settings also contains the completion sound, appearance, and the Keyboard shortcuts launcher. **System**, **Light**, and **Dark** appearance are available.

Duration, rhythm-list, alert, and appearance edits are drafts until **Save settings**. **Cancel** discards them. Saving new durations applies to future intervals; the current countdown is preserved, even if it is idle. Use the current timer's − / + controls for a change to this interval, or apply a rhythm to prepare a new interval.

Keyboard shortcuts have their own **Save shortcuts** button. Saving that editor is independent of the parent Settings sheet. The daily goal in Progress saves immediately.

## Block distractions

**Beta feature:** app and website blocking are included in [0.3.0 beta](https://github.com/albert2704/stint/releases/tag/v0.3.0-beta.1) and were introduced in 0.2.0. The older 0.1.1 download does not include them. Follow the [installation guide](install.md) and [complete blocker setup guide](blocking.md).

Open **Settings → Block distractions…** or the timer's shield control. Turn on **Block during focus**, use **Choose apps**, and add website domains or HTTP/HTTPS URLs. Choose **Save blocklist** to apply the draft; this save is independent of the parent Settings sheet. Each name covers itself and its subdomains.

Mac apps are hidden when you switch to them; their documents stay open. For websites, choose **Set up website blocker**, double-click the command revealed in Finder, complete its one-time administrator setup in Terminal, and return to **Refresh**. No Apple subscription or browser extension is needed. See [setup and recovery](blocking.md#set-up-the-website-helper).

The local proxy keeps browsers open and HTTPS encrypted. It affects browsers using macOS proxy settings, including Stint’s YouTube music. Use a built-in or local track when blocking YouTube. Loaded pages and buffered media can remain visible. Existing custom proxies, VPNs and apps that ignore system proxy settings are unsupported.

Pause, reset, skip, completion and breaks release protection. **Unblock this stint** requires confirmation and stays effective through pause/resume of that interval. If Stint crashes, a running helper detects the missing local server and restores proxy settings. A stalled timer heartbeat expires within 30 seconds. A permanently stopped helper needs [recovery](blocking.md#remove-or-recover-the-helper), because system proxy settings cannot expire themselves. Reload failed pages after release. App blocking remains independent of helper setup.

## Completion alerts

While Stint is running, a timed interval reaching zero produces a Stint card beneath the countdown and plays the selected sound **twice**, separated by a short gap. Manually ending Flow with **Take break** records the session and prepares a break without this timed alert. The direct chime is separate from macOS notification permission, but still depends on your Mac's audio output and volume.

The card shows the next interval, cycle position, and today's progress. Its title changes for a normal focus completion, the fourth focus stint, the exact daily goal, or the end of a break. Use **Start break**, **Start long break**, or **Start focus** to continue. **Skip break** prepares the next focus interval without starting it. **Not now** dismisses the break-complete card.

The card stays until dismissed or the timer moves on. It hides while the menu bar timer panel is open. It does not raise the main window on a real completion.

To preview without changing your timer:

- Choose **Stint → Preview notification**, or use the countdown's context menu. The preview is silent; its actions only dismiss it.
- Choose **Test alert sound** from either menu to hear the current two-play sound.
- In Settings, preview **Glass**, **Ping**, **Pop**, **Funk**, **Submarine**, or **Basso** before saving.

While the app is running, Notification Center receives a quiet record to avoid a second banner and sound. On a normal Quit during a running interval, Stint schedules the system notification to supply the later alert. System delivery follows macOS Notifications and Focus settings. The normal-Quit scheduling path is tested in code; audible delivery after Quit remains a live-verification limitation in this version. Force quitting is not the normal-Quit path.

## Music

### Ambient mix

Expand **Ambient mix** in Sound to set independent Rain, Café hum and Brown noise levels. The original synthesized loops play locally. Choose **Play ambience** to listen without music, or use the main sound control to play the selected track with your configured mix. Layer levels are independent of music volume. Adjusting a silent layer saves its level without starting playback.

Play with timer controls configured layers alongside the selected music. Pausing or ending the interval pauses both. Saved levels survive relaunch, but playback starts silent. You can also open the mixer from the menu bar panel.

### Built-in and imported audio

Stint includes three original instrumental loops: **Quiet Keys**, **Warm Drift**, and **Night Study**. Select a source, then press **Play**. Selection stops the previous source and does not start the newly selected one automatically. The volume control belongs to music, not the completion chime.

Choose **Add → Audio file** to import one or more files. Each must contain playable audio and be no larger than 200 MB. MP3, M4A, WAV, and AIFF are useful formats to try; actual decoding is performed by macOS. Stint copies imports into its local music library. Moving the original file afterward does not affect that copy. **Remove** deletes only Stint's copy, not the original.

If one file in a multi-file import fails validation, that selection is not partially imported. Retry with supported files.

Selection, volume, and Play with timer are remembered. Playback starts paused on launch.

### Play with timer

When this option is on, the selected music follows focus, short breaks, and long breaks:

| Timer event | Music behavior |
| --- | --- |
| Start or resume | Starts or resumes the selected source. |
| Pause or finish | Pauses playback. |
| Reset, Skip, cycle jump, or applying another rhythm | Pauses playback as the next interval is prepared. |
| Ordinary countdown tick | Leaves manual music controls alone. |

Local audio fades during linked transitions; YouTube pauses immediately. A manual music pause lasts until the next timer transition. Turning the option off leaves playback under manual control. Turning it on synchronizes to the current timer immediately. Relaunching with a restored running timer stays silent until a later transition or an explicit enable action.

### YouTube

1. Choose **Add → YouTube link**.
2. Paste a link to a single video or live stream. You may add a name of up to 120 characters.
3. Save the link, then press **Play**. **Show player** opens the menu bar panel without starting playback.

The video plays visibly inside the menu bar timer panel with YouTube's controls. Closing or hiding that panel pauses YouTube, even when Play with timer is on. The timer itself continues. Reopening the panel leaves playback paused until you press Play or a new linked timer transition requests playback.

YouTube requires internet access. Stint uses the official embedded player and does not download or extract audio. Playlist-only links are not supported; saving a video link keeps its video ID, not playlist position or a URL timestamp. Unavailable, restricted, or non-embeddable videos can fail even if they work on the YouTube website. Try another video or a local track.

## Progress

The selected week includes recorded focus time, completed session count and average session length. Average length is the arithmetic mean of completed sessions, rounded to a minute. A **weekly target** defaults to 10 hours and can be changed in 30 minute steps from 30 minutes to 100 hours. The target compares against the selected week's recorded time; it does not estimate attention or include unfinished focus. Weeks and dates continue to follow the app locale and local calendar.

Click the daily count in the main header, or **Progress** in the menu bar panel. The sheet contains today's finished stints, the weekly chart, your streak, goal days, and all-time focus time.

- Only completed focus intervals count. Breaks, resets, skips, and manual jumps do not.
- The daily goal defaults to **8** and can be changed from **1 to 16**. Changes save immediately; there is no Save button in Progress.
- A stint belongs to the local day on which it finished. The week follows the app locale. Changes of day or timezone refresh the totals.
- A streak means consecutive days with at least one stint, ending today or yesterday if today has none yet.
- Past goal days are compared with your **current** daily goal. Stint does not store a separate goal for each historical day.
- Compatible focus records in the current workspace are included. Version 0.1.1 does not import the previous app's history. The current app does not expose the former task board or note-taking features.

## Keyboard shortcuts

Open **Settings → Keyboard shortcuts**. The default scope is **Everywhere on this Mac**, while Stint is running. Choose **Only in Stint** to limit the same actions to the active app.

Hold **Control + Option + Command** and press:

| Key | Action |
| --- | --- |
| P | Start / Pause |
| R | Reset |
| N | Skip |
| S | Show timer panel |

To change a binding, click its shortcut button, then press the new combination. Include **Control** or **Command**. Supported keys include letters, digits, arrows, Space, and F1–F12. **Escape** cancels recording; switching apps also cancels it. Timer shortcuts are suspended during recording.

Use **Clear** to disable an action or **Restore defaults** to reset the editor draft. Choose **Save shortcuts** to apply it. Duplicate, reserved, unsupported, and detected conflicting combinations show an error; unsuccessful saves retain the prior saved configuration.

Bindings use physical Mac key positions. Labels follow the supported US-position key catalogue, which can differ from the printed character on another keyboard layout. The app also keeps its normal menu commands, separate from these four configurable bindings.

Reset and Skip show the existing confirmation if the interval has progress. A shortcut never bypasses that confirmation. Native registration and action routing are covered by automated checks; physical Mac-wide key delivery still needs broader device verification. See [shortcut troubleshooting](troubleshooting.md#shortcuts-do-not-trigger).

## Local data

Stint stores timer state, settings, custom rhythms, and completed sessions on your Mac. There is no Stint account or cloud synchronization. YouTube playback connects to YouTube and uses WebKit's web storage.

Version 0.1.1 uses its own Stint bundle identity, preference keys, and data folder. When upgrading from 0.1.0, quit the old app before opening the new one. Settings, history, the music library, shortcuts, and notification permissions start fresh. Your previous data stays untouched and is not imported automatically. For backup and recovery details, see [data storage](architecture.md#persistence-and-compatibility) and [troubleshooting](troubleshooting.md#stint-cannot-load-or-save-data).
