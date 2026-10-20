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
bash scripts/test-blocker.sh
bash scripts/test-hosts-blocker.sh
bash scripts/test-local-proxy.sh
bash scripts/test-proxy-preferences.sh
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
| Blocker policy and UI | App/domain validation, saved drafts, focus-only transitions, confirmed session override, helper setup status, and explicit setup/removal controls |
| Native blocker | Cooperative app hiding, deadline/lease release and confirmed override |
| Legacy hosts cleanup and helper bridge | Byte preservation, malformed markers, ownership, links, staged executable verification and version 2 policy publication using temporary fixtures |
| Local HTTP/CONNECT proxy | HTTP forwarding, verified encrypted TLS, health under load, domain changes, malformed requests, queued DNS, lease expiry and shutdown |
| Proxy preferences and recovery | Original values, commit/apply failures, journal safety, restart recovery, external edits and network service changes |

The native harnesses compile production source with warnings treated as errors. They use fakes for system settings and temporary fixtures for file changes. The transport harness uses real loopback sockets and a local TLS server; it does not change system proxy settings. The Carbon routing test delivers in-process events to the real application event target, but does not synthesize physical keyboard input.

## Focus experience source build verification

On 20 October 2026, the five additions—focus profiles, Flow, ambient layers, weekly progress and Pick up here—passed static analysis and all **216 Flutter tests**. The relevant native harnesses passed **982 checks**: 274 completion/menu bar, 71 blocker, 307 shortcuts, 128 YouTube, 170 music and 32 completion-card checks. Independent code review approved the combined change after fixes for unchanged-value save retries, the music fade's starting volume and the Flow blocker label.

Coverage includes Flow pause/recovery and delayed sleep delivery, exactly-once completion, expiring blocking leases, profile confirmation/cancellation and failure compensation, missing music fallback, ambient transport, migration, calendar-week totals and continuation persistence. Widget checks cover the supported 420 × 600 minimum size and both themes.

The Apple Silicon development app built successfully at `build/focus-experience/Stint.app` and passed deep, strict signature verification. A separate copy with its own bundle identifier and sandbox storage was used for the live walkthrough. Its entitlement to the installed website blocker's shared policy directory was removed, keeping real helper policy out of this check.

The live walkthrough verified Flow counting upward, cancelling a profile switch during Flow, recording one completed session and preparing a one-minute break, applying Writing silently, editing Pick up here, changing the weekly target, playing and pausing ambience alone, and opening the mixer from the native menu bar. After quitting and relaunching, the continuation sentence, idle timer, saved mix and 630-minute weekly target persisted, with audio paused.

These results apply to the local source build, not the published 0.2.0 beta package. Real website enforcement, physical sleep/wake, physical Intel hardware and release packaging were not re-tested for this change. Flow resumes paused from 15-second checkpoints after relaunch; quitting or crashing can lose time since the last checkpoint. Pausing first saves exact elapsed time.

## Version 0.2.0 beta verification

The beta uses a local HTTP/CONNECT proxy inside the unprivileged app. Its administrator installed helper selects the proxy during a running focus and restores the previous network settings afterward. The earlier hosts based enforcement, browser hiding guard and paid Network Extension approach are no longer used.

On 11 October 2026, static analysis and all **170 Flutter tests** passed. Native checks passed **124 legacy hosts cleanup and helper bridge**, **69 app blocker**, **710 transport**, **631 proxy preference/recovery**, and **835 existing shortcut, completion, card, music and YouTube** checks. The [CI checks](https://github.com/albert2704/stint/actions/runs/38124934395) passed for source commit `adeae3c0b5b26d786ef57d1d21619dd65e68eae5`.

The transport checks include a real certificate verified TLS handshake through CONNECT, both half close directions, twelve queued simultaneous DNS lookups, authenticated health checks at full connection capacity, malformed requests, domain changes and lease expiry. Preference checks use a fake SystemConfiguration backend and real temporary recovery journals, including uncertain commit/apply results, external edits, service changes and unsafe files. These harnesses do not install privileged software or change real network preferences.

### Live browser and recovery checks

The user completed the administrator helper upgrade. The installed helper reported version 2, proxy transport and readiness, with normal routing restored while inactive. These live checks then ran on an Apple Silicon Mac:

* An existing normal Edge window loaded YouTube before focus. During focus, navigation failed and a hard reload displayed `ERR_TUNNEL_CONNECTION_FAILED`. An existing allowed GitHub tab still loaded after a hard reload, and Edge remained accessible.
* Pausing restored the exact saved proxy dictionaries for all five network services and removed the recovery journal. Reloading YouTube then succeeded.
* Terminating the exact Stint process with `SIGKILL` while blocking was active restored the saved proxy dictionaries and removed the journal in approximately 1.01 seconds. The helper reported that the proxy was unavailable and normal settings had been restored.
* The exact universal release app was copied into the existing local app location and launched. It retained the existing progress, music selection and running timer. Blocking was active, YouTube failed with `ERR_TUNNEL_CONNECTION_FAILED`, and GitHub still loaded in Edge.

* Restarting the root helper during active focus restored the exact baseline before waiting for a fresh app heartbeat. The replacement helper then re-enabled protection. The observation log captured both the inactive recovery period and subsequent active status.
* Quitting the exact release app normally also restored the saved proxy dictionaries, removed the recovery journal and left no Stint process running. The helper used its proxy-unavailable recovery path.

After verification, the original paused 05:00 short break, cycle position, 3 of 8 daily progress and music settings were restored. Exactly one release app remained running, with the helper inactive and the saved network settings restored.

Chrome was not installed and remains unverified for this beta. These checks establish the observed Edge behavior, not universal coverage of browser versions, VPNs, cached pages or streams opened before routing changed. Physical Intel and macOS 12 testing, the downloaded app's Gatekeeper interaction and a full helper removal/reinstallation remain unverified. See [package verification](#downloadable-package-verification) and [setup and recovery](blocking.md).

### Historical hosts experiment, replaced before this beta

Earlier on 11 October, the hosts implementation passed temporary file checks and live DNS/restoration checks. It mapped YouTube to loopback during focus and restored the original hosts file and resolution on pause. The Finder setup handoff and administrator installation also worked.

Browser testing then found a failure: an existing Edge profile still loaded YouTube in a new window and after a cache bypassing reload, even though Edge and macOS both resolved the domain to loopback. A fresh InPrivate window failed with `ERR_CONNECTION_REFUSED`. Connection reuse was the leading explanation, but no individual connection was traced. Chromium can [reuse HTTP/2 sessions](https://chromium.googlesource.com/chromium/src/+/HEAD/net/spdy/spdy_session_pool.cc) without a new hostname lookup. These results motivated the local proxy replacement; DNS success was not proof of reliable browser blocking.

The beta helper removes old Stint hosts entries during upgrade and recovery. It does not add hosts entries during focus. Historical Edge tab chooser and Network Extension checks concern removed implementations and are not evidence for this proxy.

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

### Version 0.2.0 beta

**Passed on 11 October 2026:** [Package macOS run 38124929655](https://github.com/albert2704/stint/actions/runs/38124929655), at source commit `adeae3c0b5b26d786ef57d1d21619dd65e68eae5`.

The full Xcode workflow produced the universal AOT release app and passed its startup smoke check. The downloaded workflow artifact's DMG and ZIP matched their SHA256 checksums. Independent checks verified both `arm64` and `x86_64` architectures, deep strict ad hoc signatures, release entitlements, version `0.2.0` (build `3`), the declared macOS 12 minimum and absence of a debug Dart kernel. The disk image passed verification, and its app matched the ZIP copy.

The exact packaged app also launched locally on Apple Silicon and passed the Edge blocking/allowed navigation checks described above. This is separate from the earlier debug development build. The package remains ad hoc signed and is not notarized. These checks do not establish physical Intel or macOS 12 operation, Gatekeeper approval or a download and upgrade through Finder.

### Version 0.1.1 evidence

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
- Version 0.2.0 beta passed CI, universal Xcode packaging, runner bootstrap and a local release app session. Physical Intel and macOS 12 testing, Chrome, Gatekeeper interaction and a downloaded app upgrade remain unverified. The prerelease uses ad hoc signing; Apple Developer ID signing and notarization are not provided. Android is not implemented.

CI runs the same automated suites on a GitHub-hosted Mac. A green run is useful evidence for the tested commit, not a claim that all hardware and OS behaviors have been exercised.
