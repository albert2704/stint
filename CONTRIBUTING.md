# Contributing to Stint

Stint is a small macOS Pomodoro app with a Flutter interface and native menu bar, notification, audio, and shortcut services. Contributions that improve its reliability, accessibility, documentation, and everyday focus workflow are welcome.

Start with the [development guide](docs/development.md), [architecture](docs/architecture.md), and [user guide](docs/user-guide.md). The current product is Pomodoro with music and Progress. Task boards, note taking, handwriting, desktop pets, cloud sync, and Android are not implemented product surfaces in this version.

## Discuss the change

For a bug, provide reproducible steps, expected and actual behavior, macOS version, processor architecture, build route, and relevant error text. A minimal example is better than a full personal workspace. Crop screenshots and recordings to avoid exposing filenames, links, account details, or unrelated apps.

For a substantial feature or architectural change, describe the user problem and proposed behavior before investing in a large implementation. Explain how it affects the main window, menu panel, keyboard access, saved data, and the supported build routes. Small fixes and documentation corrections can go directly to a focused pull request.

## Local workflow

1. Create a branch for one coherent change.
2. Build and run the app using the [documented setup](docs/development.md).
3. Make the change with existing UI tokens and service boundaries.
4. Run checks appropriate to the affected behavior.
5. Update relevant user/developer documentation and verification evidence.
6. Open a pull request that explains the problem, resulting behavior, and actual validation.

Do not commit `.tooling/`, `build/`, `.dart_tool/`, downloaded SDKs, personal application data, credentials, signing keys, or local diagnostic dumps. Keep the package lockfile so contributors share the dependency resolution. Do not include imported audio or private YouTube links in fixtures.

## Code and compatibility

Use Dart's formatter and existing analyzer rules. Keep native builds warning-clean. Prefer existing Flutter/native APIs over adding a runtime package for a small integration.

The Dart controller owns the persistent timer and completion history. Native UI routes commands back through the bridge. Preserve the safeguards against duplicate completion, stale notification actions, delayed Pause becoming Start, and confirmations applying to a replaced interval.

Both hosts matter: `macos/Runner/MainFlutterWindow.swift` is the standard Xcode runner, while `scripts/local_macos_runner.m` is the Command Line Tools host. If you add a native source or framework, update the appropriate build script, test harness, and Xcode project integration.

Version 0.1.1 establishes the Stint identity: `io.github.albert2704.stint`, the `stint` Dart package and method channels, `Stint` native preferences, and the `Stint` support folder. It deliberately starts fresh without reading, migrating, or deleting previous app data. Do not reintroduce automatic imports or old identity fallbacks. Schema compatibility is separate: the workspace format remains version 1 and still round-trips task/note records even though those interfaces are not exposed. Any later schema change needs an explicit migration plan and tests.

Settings sheets use drafts until Save, except the immediate daily goal and the independently saved shortcut editor. Failed persistence or registration must remain visible and must not silently discard a valid saved configuration.

## Tests and evidence

At minimum for Dart changes:

```sh
bash scripts/flutter.sh analyze lib test
bash scripts/flutter.sh test --reporter expanded
```

For native changes, run the relevant harnesses:

```sh
bash scripts/test-completion-alert.sh
bash scripts/test-notification-card.sh
bash scripts/test-keymap.sh
bash scripts/test-music-state.sh
bash scripts/test-youtube-presentation.sh
```

Use meaningful behavior tests: timer transitions, save failures, stale callbacks, asynchronous cancellation, accessibility, and compatibility. Inject time, use `MemoryWorkspaceStore`, mock channels, and use fake native effects rather than modifying a real user's timer or audio library. Native harnesses should remain headless and should not play audio or register real global shortcuts.

For UI changes, check Light, Dark, and the 420 × 600 minimum window. Ensure controls have accessible names, keyboard focus is visible, and long content scrolls. For native media or keyboard changes, also perform the real-app check that the harness cannot establish.

Record the exact checks run and their outcome. Distinguish automated logic coverage from live OS behavior. Version 0.1.1 passes local analysis, Flutter tests, native harnesses, CI checks, and the Xcode package/bootstrap workflow; see [verification results](docs/testing.md). Physical global keyboard delivery across devices and audible notification delivery after Quit remain live-check limits. Do not turn those into support claims without evidence.

## Documentation and media

Keep README onboarding short and link to detailed guides. Document the final behavior rather than the conversation that led to it. Use repository-relative links and generic examples; avoid machine-specific paths and personal workspace snapshots.

Screenshots and videos should show the actual app or clearly identify an illustrative rendering. Use a fixture state without personal files or links. Include readable labels or captions, useful alternative text, and a static image when video is unnecessary. Keep source media or reproducible capture instructions where practical. Do not imply that a mockup proves native behavior.

Verify the rights to every new font, image, sound, and clip, and include its required attribution/license. macOS system alert sounds are read from the user's system at runtime; do not copy them into the repository as distributable assets.

## Pull requests

A useful description states:

- The concrete problem and resulting behavior.
- The affected surfaces or data, including compatibility implications.
- The tests and live checks actually performed.
- Any known limitation, follow-up, or behavior that remains unverified.

Keep unrelated refactors out of the change. If a specification is superseded, state the new behavior in the relevant documentation without erasing useful historical context. See [testing and verification](docs/testing.md) for examples of evidence and limits.

Contributions are expected to use the repository's [MIT license](LICENSE), with third-party material clearly identified under its own compatible terms. See [third-party notices](THIRD_PARTY_NOTICES.md) before changing bundled assets.
