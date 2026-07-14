# Testing and verification

Stint combines Flutter tests with headless Objective-C harnesses. They verify application behavior and native lifecycle logic without changing your saved workspace, posting real notifications, or playing alert sounds.

## Run the checks

From the repository root, with Flutter on `PATH` or in `.tooling/flutter`:

```sh
bash scripts/flutter.sh pub get
bash scripts/flutter.sh analyze lib test
bash scripts/flutter.sh test --reporter expanded
```

Native checks need macOS, Apple's developer tools, and the cached Flutter macOS engine. Prepare it with:

```sh
bash scripts/flutter.sh precache --macos
bash scripts/test-keymap.sh
bash scripts/test-completion-alert.sh
bash scripts/test-notification-card.sh
bash scripts/test-music-state.sh
bash scripts/test-youtube-presentation.sh
```

The framework locator supports the local build output, the repository SDK, `FLUTTER_ROOT`, and a Flutter executable on `PATH`. For custom SDK layouts, set `STINT_FLUTTER_FRAMEWORK_DIR` to the directory containing `FlutterMacOS.framework`. See [development](development.md).

## What the tests cover

| Suite | Main behaviors |
| --- | --- |
| Flutter controller and persistence | Deadline recovery, cycle migration, duration bounds, paused sessions, confirmations, atomic saves, and backup recovery |
| Flutter UI | Timer controls, compact layouts, theme variants, settings drafts, progress navigation, and accessible actions |
| Timer music | Focus and both breaks, start/pause/finish, delayed loads, manual pauses, silent launch, and stale playback requests |
| Shortcut editor | Recording and cancellation, scope, clear/defaults, independent drafts, conflicts, unavailable native support, and save failures |
| Native shortcuts | Validation, labels, registration rollback, persistence, recording cancellation, repeat suppression, stale identifiers, and Carbon event routing |
| Completion alerts | One completion per interval, two chimes, preview safety, next-interval context, notifications, and shortcut routing |
| Completion card | Geometry, screen anchoring, keyboard actions, persistent card lifecycle, and first-close hint timing |
| Native music | Playback snapshots, codec types, settings, and source state |
| YouTube | Embedded panel visibility, suspension pairing, pending playback cancellation, and stale callbacks |

The native harnesses compile production source with warnings treated as errors. They replace operating-system side effects with fakes. The Carbon routing test delivers in-process events to the real application event target, but does not synthesize physical keyboard input.

## Version 0.1.1 status

Local verification of the Stint identity change passed on 10 October 2026: static analysis is clean, all **146 Flutter tests pass**, and the five native harnesses pass **835 checks** (307 shortcuts, 266 completion, 32 card, 102 music, and 128 YouTube). The 266 completion checks also passed with the process timezone set to both UTC and Asia/Ho_Chi_Minh.

The Apple Silicon Command Line Tools development build also passed compilation and deep, strict signature verification in a separate output directory. Its bundle identifier, single `Stint` executable, display name, and version `0.1.1+2` were checked. It was not launched in the user’s profile.

The new version uses matching `stint` method channels and Dart imports, the `Stint` executable and native sources, bundle identity `io.github.albert2704.stint`, and Stint data and preference keys. Existing workspace schema compatibility tests remain; an identity break does not remove the legacy record types from the JSON format.

The [GitHub CI checks](https://github.com/albert2704/stint/actions/runs/38021166305), [Xcode package workflow](https://github.com/albert2704/stint/actions/runs/38021166173), and exact-app startup check also passed at source commit `82623f112378771dfda20892f4dc0c36ae95d997`. This establishes automated checks and CI bootstrap under the new identity. It does not establish the downloaded app's Gatekeeper flow, a manual upgrade, or unchanged previous data during a live installation. The historical baseline below belongs to version 0.1.0.

## Historical baseline for version 0.1.0

On 10 October 2026, the feature baseline passed static analysis and **146 Flutter tests**. Native harness totals were **307** shortcut checks, **266** completion checks, **32** card checks, **102** music checks, and **128** YouTube checks.

The Apple Silicon Command Line Tools development build was built and its code signature verified. The shortcut editor, recording, separate shortcut save, and music starting and pausing with a short break were checked in the running app. Screenshot fixtures use synthetic data, rather than a user's saved history.

The initial public source files also built successfully in a clean temporary checkout, using Flutter from `PATH` and a shared package cache. Static analysis and all 146 Flutter tests passed in that copy. No private design handoff files or project-local SDK were present. These checks verify the documented local packaging route and tests against the files being published.

## Downloadable package verification

**Version 0.1.1 passed on 10 October 2026:** [Package macOS run 38021166173](https://github.com/albert2704/stint/actions/runs/38021166173), at source commit `82623f112378771dfda20892f4dc0c36ae95d997`.

The full Xcode workflow built the release app and verified `arm64` and `x86_64` slices in its executable and frameworks, its strict ad hoc signature, release sandbox entitlements without JIT/debugger access, absence of a debug Dart kernel, version `0.1.1`, and the declared macOS 12 minimum. DMG verification and SHA256 checksum generation completed successfully.

The exact staged app stayed alive on the disposable GitHub runner and created its sandbox data directory under the new Stint identity. The smoke check then terminated it. This verifies bootstrap, not a full UI session or the downloaded app's first launch. Physical Intel and macOS 12 testing, Gatekeeper interaction, and a manual upgrade remain unverified.

The downloaded 0.1.1 DMG and ZIP both matched their SHA256 values. The extracted ZIP app passed deep, strict signature verification; its bundle identity `io.github.albert2704.stint`, display name and executable `Stint`, version `0.1.1`, build `2`, and minimum macOS `12.0` matched the release. The executable and both frameworks contained `arm64` and `x86_64` slices. Release entitlements retained sandbox and network access without JIT or debugger access, and the native/Dart app binaries contained no previous branding strings. The downloaded disk image passed `hdiutil verify`; mounted read-only, its app passed strict signature verification, its executable matched the ZIP copy, and its Stint identity, Applications shortcut, and installation text were checked. Version 0.1.1 was not launched for a local UI check.

### Version 0.1.0 evidence

**Passed on 10 October 2026:** [Package macOS run 38019933799](https://github.com/albert2704/stint/actions/runs/38019933799), at source commit `1c2e3d3`, built the v0.1.0 universal release with full Xcode on an Apple Silicon GitHub runner. This is separate from the earlier Command Line Tools debug build.

[`scripts/package-macos.sh`](../scripts/package-macos.sh) completed these checks:

- Full Xcode release build with `arm64` and `x86_64` slices verified in the app executable, `App.framework`, and `FlutterMacOS.framework`.
- Deep, strict verification of the ad hoc app signature and its embedded frameworks.
- No debug Dart kernel, with sandbox/network client entitlements present and JIT/debugger entitlements absent.
- App version `0.1.0` and declared minimum macOS version `12.0`.
- DMG verification and SHA256 checksum generation for the DMG and ZIP archives.

The [development guide](development.md#package-a-downloadable-prerelease) gives the reproduction command and output paths.

The manual [Package macOS workflow](../.github/workflows/package-macos.yml) also passed [`scripts/smoke-release-macos.py`](../scripts/smoke-release-macos.py) on the disposable Apple Silicon runner. The exact staged app stayed alive, and Flutter/native startup created its sandbox data directory. The check terminated that process afterward. It did not interact with a contributor's saved workspace and refuses to run outside the expected CI environment.

These results establish both architecture slices and startup on the runner's Apple Silicon host. Physical Intel and macOS 12 device testing, the downloaded app's Gatekeeper flow, and a manual install/upgrade have not been verified. Bootstrap is not a full UI session and does not exercise every timer, music, or notification action.

The downloaded v0.1.0 DMG and ZIP passed SHA256 comparison on an Apple Silicon Mac. The extracted ZIP app passed strict signature verification and contained both architectures in its executable and frameworks. The disk image passed `hdiutil verify`. A copied release bundle with a separate test identifier opened the interface and passed Start/Pause interaction checks; the published bundle was not modified. This isolated UI check does not establish an upgrade or Gatekeeper flow with the production app identity.

## Limits and manual checks

- Physical Mac-wide shortcut delivery remains a manual check. Targeted UI automation can reach the app's shortcut recorder without going through system hotkey matching. Registration success and headless routing tests do not prove hardware-key delivery from another app.
- Test **Control + Option + Command + S** while another app is active. The timer panel should appear. Test Start/Pause next; Reset and Skip should show confirmation when the interval has unfinished time.
- YouTube needs real network and embedding permission for the chosen video. Headless tests cannot guarantee availability of a third-party stream.
- System notification presentation depends on macOS permissions and Focus settings. A normal-Quit notification should also be tested on a real Mac.
- Version 0.1.1 passed CI, universal Xcode packaging, and runner bootstrap checks. Physical Intel and macOS 12 testing, Gatekeeper interaction, and a manual upgrade remain unverified. The prerelease uses ad hoc signing; Apple Developer ID signing and notarization are not provided. Android is not implemented.

CI runs the same automated suites on a GitHub-hosted Mac. A green run is useful evidence for the tested commit, not a claim that all hardware and OS behaviors have been exercised.
