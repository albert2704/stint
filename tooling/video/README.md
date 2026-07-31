# Stint demo source

A 30-second feature overview for Stint's 0.2.0 blocker beta, with Stint’s original Quiet Keys music, built with HyperFrames. The composition shows actual Stint Flutter widget-test screenshots. It is a designed overview, not a recording of mouse or keyboard interaction.

## Reproduce

Requires Node.js 22 or later, npm, Chrome/Chromium, and FFmpeg. HyperFrames 0.8.147 and the other exact JavaScript dependency versions are pinned in `package-lock.json`. These tools are only needed to regenerate documentation media; they are not part of the Stint app build.

```sh
cd tooling/video
npm ci
npm run check -- --at 2,7,12,17,22,27
npm run dev
```

The preview opens HyperFrames Studio, where the scenes can be edited. After reviewing:

```sh
npm run render
npm run snapshot
cp renders/still/frame-00-at-2s.png ../../docs/media/stint-overview.png
bash export-gif.sh
```

`npm run render` produces `docs/media/demo.mp4` at 1280×720, 30 fps, 30 seconds. `export-gif.sh` creates a smaller 800-pixel-wide, 8 fps looping GIF from that MP4 using FFmpeg's palette pass. `npm run snapshot` captures the same first scene at two seconds for the README hero.

## Files

- `index.html`: 30-second parent timeline and persistent Stint header.
- `compositions/frames/1.html`, `2.html`, `3.html`, `blocker.html`, `4.html`, `5.html`: six editable scenes in playback order, five seconds each.
- `assets/`: fixture screenshots, app icon, and local font files.
- `.media/audio/bgm/bgm_001.wav`: frozen copy of the repository’s original Quiet Keys track.
- `BRIEF.md`, `STORYBOARD.md`, `frame.md`: intent, timings, and visual choices.
- `capture/extracted/` and `.media/manifest.jsonl`: asset descriptions and provenance.
- `capture/capture_blocker_test.dart`: isolated media fixture that captures the real Block distractions widget without operating the native app or network helper.

Motion uses deterministic paused GSAP timelines: sliding feature transitions, screenshot settle/push motion, a filling progress ring and cycle, a drawn rhythm callout, an animated waveform, focus/pause chips, growing progress marks, and a sequenced closing invitation. These accents sit outside the screenshots and are illustrative; they do not simulate app interactions or modify captured timer values. Images remain faithful to the app; the music scene crops the existing screenshot without changing the controls. The disabled switch in the screenshot is intentional: its callout explains turning the option on.

The blocker appears at 15–20 seconds, progress at 20–25 seconds, and the download invitation at 25–30 seconds. The ending points to [stint-focus.vercel.app](https://stint-focus.vercel.app/), with free/MIT licensing and the macOS 12+, Apple silicon and Intel package targets. Release verification limits remain in the [beta notes](../../docs/releases/v0.2.0-beta.1.md).

## Refresh app screenshots

From the repository root, regenerate the original fixture captures:

```sh
bash scripts/flutter.sh test test/pomodoro_ui_test.dart test/progress_test.dart
```

Review `docs/screenshots/stint-{dark,light,settings}.png` and `docs/screenshots/progress-{dark,light}.png`, then copy the approved images into both `assets/` here and `docs/media/`.

Regenerate the blocker capture separately, also from the repository root:

```sh
bash scripts/flutter.sh test tooling/video/capture/capture_blocker_test.dart
```

This writes the same 720×720 PNG to `tooling/video/assets/stint-blocker.png` and `docs/media/stint-blocker.png`. It uses `BlockerSettingsDialog`, Stint's theme and fonts, and a synthetic controller with Chat (`com.example.chat`) and `youtube.com` selected. The fixture represents an enabled, running focus with an active helper; it does not install or contact that helper, change network settings, or read a personal workspace. Its active status demonstrates the UI and is not evidence of a live blocking check.

Do not substitute a personal desktop capture or real session history. Re-run the checks, inspect all six scenes, and render again. The blocker remains labeled beta: selected apps hide, website connections are blocked while focus runs, and pausing releases blocking. Website protection needs administrator setup and a browser using macOS proxy settings. See [setup and limits](../../docs/blocking.md).

## Licenses and services

Stint's original composition, copy, screenshots, and icon are covered by the repository's MIT license. The fonts retain their separate SIL Open Font License notices beside the files. GSAP 3.14.2 is an npm dependency under its [own license](https://gsap.com/standard-license/); it is not relicensed under MIT. HyperFrames and its transitive dependencies retain the licenses supplied in their installed packages. No `node_modules` are committed.

No external images, narration, YouTube content, or personal data are included. Quiet Keys is an original synthesized Stint track, covered by the repository’s MIT license; its generator is `scripts/generate_focus_music.py` at the repository root. No HeyGen generation service was used.

## Audio mix

The MP4 uses the first 30 seconds of the 32-second stereo Quiet Keys WAV. `index.html` declares the track and its volume envelope: 0.8-second fade-in, 70% amplitude through 28.7 seconds, then a 1.3-second fade-out. HyperFrames owns playback and exports AAC stereo audio. There is no narration or extra sound effect. The GIF remains silent.

The export's dimensions, duration, audio measurements and verification results are recorded in [`docs/media/manifest.json`](../../docs/media/manifest.json). Refresh those measurements after rendering; values from the earlier 25-second export do not describe this edition.
