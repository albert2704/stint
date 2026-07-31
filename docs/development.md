# Developing Stint

Stint combines a Flutter interface with small native macOS services. The verified development route builds an Apple Silicon debug app using Apple's Command Line Tools. A standard Flutter/Xcode project is also included, but its release build has not been verified in the current project environment.

[Architecture](architecture.md) · [Contributing](../CONTRIBUTING.md) · [Troubleshooting](troubleshooting.md) · [README](../README.md)

## Requirements and supported routes

| Item | Current status |
| --- | --- |
| Runtime target | macOS 12.0 or later in the native build configuration. |
| Verified local architecture | Apple Silicon (`arm64`). |
| Development toolchain | Flutter, Dart, Apple's Command Line Tools, and the macOS SDK. |
| Last recorded Flutter toolchain | Flutter 3.47.6 / Dart 3.13.5. |
| Standard Xcode host | Included; full Xcode build and release packaging remain unverified. |
| Intel Mac | The local helper rejects non-arm64 hosts. The standard Xcode route is a possible porting path, not a verified binary. |
| Android / iOS / Windows / Linux / web | Not implemented or supported by this repository's native services. |
| Distribution | No Developer ID signing, notarization, updater, or App Store release is configured. |

The Dart SDK constraint is declared in [pubspec.yaml](../pubspec.yaml); it is not a promise that every Flutter version satisfying that constraint has been tested. `pubspec.lock` records package resolution. There are no third-party runtime packages; development dependencies include Flutter's test framework and lint rules.

## Get a working checkout

Clone or download this repository and open a terminal in its root. Install Flutter using the [official Flutter installation guide](https://docs.flutter.dev/install), with its `bin` directory on `PATH`. Install Apple's Command Line Tools if they are missing:

```sh
xcode-select --install
```

Check the tools before building:

```sh
xcode-select -p
xcrun --sdk macosx --show-sdk-path
bash scripts/flutter.sh --version
bash scripts/flutter.sh doctor -v
```

The wrapper prefers a checkout-local SDK at `.tooling/flutter`, then a `flutter` executable on `PATH`. It keeps the Dart package cache and tool configuration under `.tooling/`, disables Flutter analytics for these invocations, and enables CI mode. Flutter itself is not vendored into the public repository. Do not commit `.tooling/`, downloaded engines, or build outputs.

The first build needs internet access to resolve development packages and obtain the official Flutter macOS engine. Built-in music and the timer can run offline after the build; YouTube cannot.

## Apple Silicon build with Command Line Tools

From the repository root:

```sh
bash scripts/build-local-macos.sh
open 'build/local/Stint.app'
```

The script fetches dependencies, precaches the macOS engine, assembles Flutter debug assets, compiles the Objective-C host and native services, installs the supplied icon resources, and signs the result locally with an ad hoc signature. It verifies that signature before reporting success. This signature supports local development; it is not Developer ID distribution signing.

The output is `build/local/Stint.app`. Its executable retains the name `FocusDesk`, and its bundle identifier remains `com.focusdesk.focusDesk` for compatibility.

Do not overwrite an app bundle while that copy is running. Build beside it with `STINT_APP_DIR`:

```sh
STINT_APP_DIR="$PWD/build/verified/Stint.app" bash scripts/build-local-macos.sh
codesign --verify --deep --strict 'build/verified/Stint.app'
open 'build/verified/Stint.app'
```

Quit the earlier app first before opening the alternate bundle. Both bundles use the same application identity and local data; they are not isolated test profiles. Use controlled fixtures for destructive tests instead of a personal workspace.

The helper packages a debug engine; it is not a replacement for a complete distribution pipeline. Rebuild and relaunch this bundle after source changes. Use the standard Flutter route below if you need Flutter's normal `run` workflow and have a suitable Xcode installation.

## Standard Flutter / Xcode route

The checked-in `macos/` directory contains the Swift runner, Xcode project, bridge declarations, native source build phases, resources, and entitlements. After configuring full Xcode for Flutter, the expected commands are:

```sh
bash scripts/flutter.sh pub get
bash scripts/flutter.sh run -d macos
bash scripts/flutter.sh build macos --release
```

These are the standard project entry points, **not recorded successful builds for this project**. Validate them on a full Xcode machine before documenting support or publishing a binary. Native changes may require updating both the Xcode project and the Command Line Tools script. Do not assume a Swift runner change affects the separate local Objective-C host.

## Checks

Run Dart analysis and the Flutter suite:

```sh
bash scripts/flutter.sh analyze lib test
bash scripts/flutter.sh test --reporter expanded
```

Run the native harnesses on a Mac with the Flutter macOS engine cached. The development build already obtains it; otherwise run the precache command first:

```sh
bash scripts/flutter.sh precache --macos
bash scripts/test-completion-alert.sh
bash scripts/test-notification-card.sh
bash scripts/test-keymap.sh
bash scripts/test-music-state.sh
bash scripts/test-youtube-presentation.sh
```

| Check | Main coverage |
| --- | --- |
| Flutter suite | Timer transitions, persistence and migration, rhythms, confirmations, Progress, widget layouts, accessibility semantics, native channel contracts, and playback coordination. |
| Completion harness | Expiry ordering, duplicate prevention, notification metadata/actions, two-play alerts, keymap routing, and stale-context rejection. |
| Notification card harness | Geometry, anchoring, persistent cards, preview/hint lifecycle, accessibility text, and action ordering. |
| Keymap harness | Validation, registration rollback, saved settings, recording lifecycle, repeat suppression, and event dispatch. |
| Music harness | Native state, Boolean codec values, selection, playing/starting/paused state, and timer-follow preferences. |
| YouTube harness | Visibility, WebKit suspension pairing, delayed events, cancellation, and stale playback intent. |

The native framework locator checks an explicit `STINT_FLUTTER_FRAMEWORK_DIR`, assembled `build/local/frameworks`, the checkout-local SDK cache, `FLUTTER_ROOT`, then the Flutter executable on `PATH`. The override must name the directory containing `FlutterMacOS.framework`; an invalid explicit override fails instead of silently using another SDK. The locator itself does not download anything.

Native harnesses use fake effects and do not play audio or register real system-wide shortcuts. They compile production code with warnings treated as errors. They establish logic correctness; a fake WebKit or registration test cannot establish real network playback or physical keyboard delivery.

For a focused Dart change, run its relevant tests first, then the full suite if it affects shared timer or bridge behavior. Do not update screenshot fixtures merely to hide a regression. See [testing and verification](testing.md) for recorded results and explicit live limits.

## Manual checks before sharing a build

Use a disposable or backed-up workspace and note the initial timer, phase, music selection, and settings.

1. Start, pause, and resume from the main window and menu panel. Confirm both show the same interval. Close the main window and confirm the countdown remains in the menu bar.
2. With elapsed time, request Reset and Skip; cancel each. Confirm both surfaces show the same pending action and do not add completed history.
3. Preview the notification and alert separately. A notification preview must be silent and leave the timer untouched. The alert test should play twice.
4. Enable Play with timer. Start and pause a focus or break interval, then manually pause music while the timer continues. Ordinary ticks must not restart it.
5. Open YouTube in the menu panel, play, hide, reopen, and play again. Hiding must pause; reopening must remain paused; a stale load callback must not restart playback.
6. Record and save a shortcut. Try the physical keyboard from another foreground app. Reset and Skip must retain confirmation. Cancel recording with Escape and by changing apps.
7. Review Light, Dark, and the minimum 420 × 600 window. Check scrolling and keyboard focus in Settings, Progress, and Keyboard shortcuts.
8. Quit and relaunch. Confirm saved settings/history remain and music stays silent.

Report which checks were actually performed. Do not treat successful registration as proof of physical global keyboard delivery, or notification scheduling as proof of later audible system delivery.

## Useful diagnostics

The local host accepts a read-only notification diagnostic:

```sh
'build/local/Stint.app/Contents/MacOS/FocusDesk' --notification-status
```

It reports the app's notification authorization and pending/delivered notification state. Review output before posting it publicly: notification metadata can include personal session information. Build logs, framework caches, and generated binaries belong under `build/`, not in source commits.

To regenerate the three built-in focus loops, inspect and run [generate_focus_music.py](../scripts/generate_focus_music.py). Its optional authoring dependency is Python 3 with NumPy; use a virtual environment for that tool. NumPy is not an app runtime dependency. Treat audio changes as user-visible asset changes: listen to the result, compare file size and loop boundaries, and document any new dependency or licensing source.

## Preparing a release

Source availability does not make a locally built debug bundle a distributable release. Before shipping a download, establish a tested release host, supported architecture/OS matrix, versioned artifact names, Developer ID signing and notarization, and a clean install/upgrade test. Include licenses for bundled material and publish checksums for the exact artifact. Keep signing credentials and private user data out of the repository.

These release tasks are not currently configured. Contributions that add them should document the exact commands and preserve the compatibility and data-protection rules in [CONTRIBUTING.md](../CONTRIBUTING.md).
