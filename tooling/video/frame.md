---
name: Stint — animated app overview
based_on: Blue Professional frame preset, adapted to Stint's dark palette
canvas: 1280x720
colors:
  background: '#101113'
  surface: '#1B1C1F'
  heading: '#EDECEA'
  body: '#ABAFB7'
  focus: '#F88932'
  break: '#78B9E6'
  border: '#36393E'
typography:
  heading: { family: HankenGrotesk, weight: 700, size: 68, lineHeight: 1.24 }
  body: { family: HankenGrotesk, weight: 400, size: 23, lineHeight: 1.45 }
  chrome: { family: MartianMono, weight: 400, size: 11 }
spacing:
  horizontalMargin: 64
  headerTop: 42
  copyTop: 172
  footerBottom: 37
---

# Visual direction

Stint's orange focus and blue break colors sit on the actual app's dark canvas. Use generous negative space, readable sentence-case headings, hairline borders, and no decorative shadows. The real app screenshot is the evidence, with supporting copy on the left. The light appearance appears in the final scene.

# Motion direction

The five scenes last five seconds each. Headline lines arrive in sequence, while app screenshots settle from a small offset/tilt and gently push during the reading hold. The inner scene content slides and fades at each boundary; the header stays stable.

Each scene has one illustrative accent outside the app capture:

1. An angular progress ring plus filling orange/blue cycle segments.
2. A drawn leader callout and sequential rhythm-chip highlights.
3. A finite, deterministic orange/blue waveform and traveling playhead.
4. Three growing progress marks and a one-session-at-a-time note.
5. A sequenced Build / Tweak / Share invitation and the repository address.

The thin header progress strip follows film time. None of these accents changes captured timer values, toggles a real setting, or depicts a simulated click. Quiet Keys provides a soft music bed with short entrance and exit fades. The GIF stays silent.

# Reproduction and accessibility

All fonts are local files, with their upstream licenses beside them. Every timeline is paused and seekable. Motion uses explicit from/to states and finite repeats. Keep copy in place long enough to read and preserve contrast against the dark canvas. Checks cover the assembled scenes at early, middle, and late proof times. Native app screenshots are immutable inputs; regenerate them from widget tests when the UI changes.
