# Stint demo source

A 25-second feature overview with Stint’s original Quiet Keys music built with HyperFrames. The composition shows actual Stint Flutter widget-test screenshots. It is a designed overview, not a recording of mouse or keyboard interaction.

## Reproduce

Requires Node.js 22 or later, npm, Chrome/Chromium, and FFmpeg. The exact JavaScript dependency versions are pinned in `package-lock.json`. These tools are only needed to regenerate documentation media; they are not part of the Stint app build.

```sh
cd tooling/video
npm ci
npm run check -- --at 2,7,12,17,22
npm run dev
```

The preview opens HyperFrames Studio, where the scenes can be edited. After reviewing:

```sh
npm run render
npm run snapshot
cp renders/still/frame-00-at-2s.png ../../docs/media/stint-overview.png
bash export-gif.sh
```

`npm run render` produces `docs/media/demo.mp4` at 1280×720, 30 fps, 25 seconds. `export-gif.sh` creates a smaller 800-pixel-wide, 8 fps looping GIF from that MP4 using FFmpeg's palette pass. `npm run snapshot` captures the same first scene at two seconds for the README hero.

## Files

- `index.html`: 25-second parent timeline and persistent Stint header.
- `compositions/frames/1.html` through `5.html`: five editable scenes, five seconds each.
- `assets/`: fixture screenshots, app icon, and local font files.
- `.media/audio/bgm/bgm_001.wav`: frozen copy of the repository’s original Quiet Keys track.
- `BRIEF.md`, `STORYBOARD.md`, `frame.md`: intent, timings, and visual choices.
- `capture/extracted/` and `.media/manifest.jsonl`: asset descriptions and provenance.

Motion uses deterministic paused GSAP timelines: sliding feature transitions, screenshot settle/push motion, a filling progress ring and cycle, a drawn rhythm callout, an animated waveform, growing progress marks, and a sequenced closing invitation. These accents sit outside the screenshots and are illustrative; they do not simulate app interactions or modify captured timer values. Images remain faithful to the app; the music scene crops the existing screenshot without changing the controls. The disabled switch in the screenshot is intentional: its callout explains turning the option on.

## Refresh app screenshots

From the repository root, regenerate the original fixture captures:

```sh
bash scripts/flutter.sh test test/pomodoro_ui_test.dart test/progress_test.dart
```

Review `docs/screenshots/stint-{dark,light,settings}.png` and `docs/screenshots/progress-{dark,light}.png`, then copy the approved current images into both `assets/` here and `docs/media/`. Do not substitute a personal desktop capture or real session history. Re-run the checks, review all five scenes, and render again.

## Licenses and services

Stint's original composition, copy, screenshots, and icon are covered by the repository's MIT license. The fonts retain their separate SIL Open Font License notices beside the files. GSAP 3.14.2 is an npm dependency under its [own license](https://gsap.com/standard-license/); it is not relicensed under MIT. HyperFrames and its transitive dependencies retain the licenses supplied in their installed packages. No `node_modules` are committed.

No external images, narration, YouTube content, or personal data are included. Quiet Keys is an original synthesized Stint track, covered by the repository’s MIT license; its generator is `scripts/generate_focus_music.py` at the repository root. No HeyGen generation service was used.

## Audio mix

The MP4 uses the first 25 seconds of the 32-second stereo Quiet Keys WAV. `index.html` declares the track and its volume envelope: 0.8-second fade-in, 70% amplitude through 23.7 seconds, then a 1.3-second fade-out. HyperFrames owns playback and exports AAC stereo audio. There is no narration or extra sound effect. The GIF is unchanged and remains silent.

The checked export has a measured mean level of −26.7 dBFS and a peak of −11.4 dBFS. Decoding the AAC output confirms approximately 0.70 amplitude through the middle of the clip and the expected entrance/exit fades. These measurements describe the committed export, not a loudness target for every future soundtrack.
