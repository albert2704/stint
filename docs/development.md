# Developing Stint

Stint combines a Flutter interface with small native macOS services. The local development route builds an Apple Silicon debug app using Apple's Command Line Tools. A separate full Xcode workflow builds a universal release app and downloadable DMG and ZIP files. Version 0.1.1 passed the [packaging workflow](https://github.com/albert2704/stint/actions/runs/38021166173) and [CI checks](https://github.com/albert2704/stint/actions/runs/38021166305).

[Architecture](architecture.md) · [Contributing](../CONTRIBUTING.md) · [Troubleshooting](troubleshooting.md) · [README](../README.md)

## Requirements and supported routes

| Item | Current status |
| --- | --- |
| Runtime target | macOS 12.0 or later in the native build configuration. |
| Local development architecture | Apple Silicon (`arm64`); the 0.1.1 local build and strict signature check passed. |
| Development toolchain | Flutter, Dart, Apple's Command Line Tools, and the macOS SDK. |
| Last recorded Flutter toolchain | Flutter 3.47.6 / Dart 3.13.5. |
| Xcode release packaging | `scripts/package-macos.sh` builds `arm64` and `x86_64`; package and CI bootstrap checks passed for 0.1.1. |
| Intel Mac | The universal workflow targets an Intel slice, but no physical Intel run has been verified. The local debug helper remains arm64 only. |
| Android / iOS / Windows / Linux / web | Not implemented or supported by this repository's native services. |
| Distribution | The prerelease workflow uses ad hoc signing. Developer ID signing, notarization, an updater, and an App Store release are not configured. |

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

The output is `build/local/Stint.app`, with executable `Stint` and bundle identifier `io.github.albert2704.stint`. The Dart package and channel prefix are `stint`. Version 0.1.1 uses a fresh `Stint` data folder and native preference keys; it does not read, migrate, or delete data belonging to 0.1.0.

Do not overwrite an app bundle while that copy is running. Build beside it with `STINT_APP_DIR`:

```sh
STINT_APP_DIR="$PWD/build/verified/Stint.app" bash scripts/build-local-macos.sh
codesign --verify --deep --strict 'build/verified/Stint.app'
open 'build/verified/Stint.app'
```

Quit any earlier app first before opening the alternate bundle. Current local and verified 0.1.1 bundles share the same application identity and local data; they are not isolated test profiles. Version 0.1.0 has a different identity and its data is left untouched. Use controlled fixtures for destructive tests instead of a personal workspace.

The helper packages a debug engine for Apple Silicon. Rebuild and relaunch this bundle after source changes. Use the standard Flutter route below for Flutter's normal `run` workflow, or [release packaging](#package-a-downloadable-prerelease) for a universal app, with a suitable full Xcode installation.

## Standard Flutter / Xcode route

The checked-in `macos/` directory contains the Swift runner, Xcode project, bridge declarations, native source build phases, resources, and entitlements. After configuring full Xcode for Flutter, the expected commands are:

```sh
bash scripts/flutter.sh pub get
bash scripts/flutter.sh run -d macos
bash scripts/flutter.sh build macos --release
```

These are the standard project entry points; their results should be verified on the machine you use. For the downloadable prerelease, use `scripts/package-macos.sh` instead of treating a raw Flutter output as a finished distribution. Native changes may require updating both the Xcode project and the Command Line Tools script. Do not assume a Swift runner change affects the separate local Objective-C host.

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
'build/local/Stint.app/Contents/MacOS/Stint' --notification-status
```

It reports the app's notification authorization and pending/delivered notification state. Review output before posting it publicly: notification metadata can include personal session information. Build logs, framework caches, and generated binaries belong under `build/`, not in source commits.

To regenerate the three built-in focus loops, inspect and run [generate_focus_music.py](../scripts/generate_focus_music.py). Its optional authoring dependency is Python 3 with NumPy; use a virtual environment for that tool. NumPy is not an app runtime dependency. Treat audio changes as user-visible asset changes: listen to the result, compare file size and loop boundaries, and document any new dependency or licensing source.

## Package a downloadable prerelease

This path requires **full Xcode**, Flutter on `PATH` or in `.tooling/flutter`, Python 3, and the macOS tools included with Xcode and macOS. Command Line Tools alone are insufficient. The script reads the version from `pubspec.yaml`.

```sh
bash scripts/package-macos.sh
```

The script configures the macOS release project through Flutter, then calls Xcode directly for both `arm64` and `x86_64`. This produces ahead-of-time compiled Dart code, without a debug kernel. The direct Xcode step preserves the checked-in release sandbox entitlements instead of allowing Flutter's CI development override to replace them.

It copies the generated app to `build/package-stage/Stint.app`, includes project, font, Flutter, and engine license notices, applies an ad hoc signature, and creates these files for version 0.1.1:

| Output in `build/distribution/` | Purpose |
| --- | --- |
| `Stint-0.1.1-macos-universal.dmg` | Disk image containing the app, an Applications shortcut, and installation text. |
| `Stint-0.1.1-macos-universal.zip` | Archive containing the same app and installation text. |
| `SHA256SUMS.txt` | SHA256 values for the DMG and ZIP. |
| `entitlements.plist` | Entitlements extracted from the signed app for verification. |

The versioned filenames change with `pubspec.yaml`. Repeating the command replaces generated packaging files; the script clears `build/package-stage/`. It does not install the app in Applications or launch it in your personal profile.

The script checks the app's signature, both architecture slices in the executable and two framework binaries, absence of a debug Dart kernel, the version and macOS 12 minimum in the bundle, and release sandbox entitlements. It rejects debug JIT and debugger entitlements, verifies the disk image, and calculates archive checksums. These checks passed for v0.1.1; see [verification results and limits](testing.md#downloadable-package-verification).

### Build in GitHub Actions

The [Package macOS workflow](../.github/workflows/package-macos.yml) has a manual `workflow_dispatch` trigger. In GitHub, open **Actions → Package macOS → Run workflow**, select the intended branch, and start the run. It installs the pinned Flutter SDK and runs the same packaging script on a hosted Mac.

On success, the run preserves a **stint-macos-preview** artifact containing the DMG, ZIP, checksums, entitlements, and bootstrap log for 14 days. This artifact is a CI download, not an automatically published GitHub release. Check the selected commit and run result before attaching files to a release.

The workflow sets `STINT_PACKAGE_SMOKE_TEST=1` to run [smoke-release-macos.py](../scripts/smoke-release-macos.py) against the exact staged app before archiving it. The check requires a disposable GitHub runner with no existing Stint data folder. It confirms that the process remains alive and Flutter/native startup creates the expected sandbox data directory, then terminates the process. It refuses to run as a local profile test. Do not fake the runner environment to bypass that protection.

This smoke check exercises only the runner's host architecture and startup. It does not prove the Intel slice on physical hardware, a full UI session, imported media, or Gatekeeper's downloaded-app experience.

### Release verification and publication

Version 0.1.1 passed [CI checks](https://github.com/albert2704/stint/actions/runs/38021166305) and the [Xcode package workflow](https://github.com/albert2704/stint/actions/runs/38021166173) on 10 October 2026 at source commit `82623f1`, including release bootstrap under the new identity. The [release notes](releases/v0.1.1.md) and [installation guide](install.md) describe its fresh app identity and downloads. Physical Intel and macOS 12 testing, the downloaded app's Gatekeeper flow, and a manual upgrade remain unverified.

For later releases, check the exact artifacts and their checksums, review the bootstrap log, and document the install/upgrade checks actually performed before publishing. A successful CI run does not replace device testing or establish Apple approval.

Ad hoc signing verifies bundle integrity but does not establish an Apple Developer ID. This workflow does not notarize or staple the app, and a downloaded build can trigger Gatekeeper. Publish it as a prerelease with that limitation stated clearly. A future trusted distribution route needs Developer ID signing and notarization; keep signing credentials out of the repository and preserve the compatibility rules in [CONTRIBUTING.md](../CONTRIBUTING.md).
