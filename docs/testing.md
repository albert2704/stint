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

## Baseline for the initial public source release

On 10 October 2026, the feature baseline passed static analysis and **146 Flutter tests**. Native harness totals were **307** shortcut checks, **266** completion checks, **32** card checks, **102** music checks, and **128** YouTube checks.

The Apple Silicon Command Line Tools development build was built and its code signature verified. The shortcut editor, recording, separate shortcut save, and music starting and pausing with a short break were checked in the running app. Screenshot fixtures use synthetic data, rather than a user's saved history.

The initial public source files also built successfully in a clean temporary checkout, using Flutter from `PATH` and a shared package cache. Static analysis and all 146 Flutter tests passed in that copy. No private design handoff files or project-local SDK were present. These checks verify the documented local packaging route and tests against the files being published.

## Limits and manual checks

- Physical Mac-wide shortcut delivery remains a manual check. Targeted UI automation can reach the app's shortcut recorder without going through system hotkey matching. Registration success and headless routing tests do not prove hardware-key delivery from another app.
- Test **Control + Option + Command + S** while another app is active. The timer panel should appear. Test Start/Pause next; Reset and Skip should show confirmation when the interval has unfinished time.
- YouTube needs real network and embedding permission for the chosen video. Headless tests cannot guarantee availability of a third-party stream.
- System notification presentation depends on macOS permissions and Focus settings. A normal-Quit notification should also be tested on a real Mac.
- The Xcode release build, Intel hardware, code signing for distribution, and notarization are not verified release paths yet. Android is not implemented.

CI runs the same automated suites on a GitHub-hosted Mac. A green run is useful evidence for the tested commit, not a claim that all hardware and OS behaviors have been exercised.
