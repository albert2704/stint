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

Stint's orange focus and blue break colors sit on the actual app's dark canvas. Use generous negative space, readable sentence-case headings, hairline borders, and no decorative shadows. Real fixture screenshots form the base for illustrative UI overlays, with supporting copy on the left. The light appearance appears in the final scene.

# Motion direction

The six scenes last five seconds each. App screenshots hold a fixed position and fade in; headlines or individual words arrive in sequence. Scene content fades between features while the header stays stable. The download invitation holds through the final frame.

Illustrative overlays and supporting accents:

1. Countdown digits over the timer, plus an angular progress ring and filling orange/blue cycle segments.
2. Classic-to-Deep-work values and radio selection over settings, plus a drawn leader callout and rhythm-chip highlights.
3. Word-by-word copy, a finite orange/blue waveform and a traveling playhead beside the unchanged sound-panel crop.
4. An off-to-on switch/status overlay over the blocker, focus/pause chips, an administrator-setup note and the browser-open message.
5. Masks revealing existing chart bars and daily segments, three growing progress marks and a one-session-at-a-time note.
6. A volume overlay from 20% to 35%, sound-icon motion, a sequenced Focus / Rest / Repeat invitation and the website address.

The thin header progress strip follows film time. Timer, settings, blocker and volume overlay states are illustrative, not live actions or an exact interaction sequence. The blocker base is a 720×720 capture of the real Flutter widget with synthetic selection and status; keep the beta and animated-demo labels visible. Quiet Keys provides a soft music bed with a 0.8-second entrance fade and a 1.3-second exit fade over the 30-second film. The GIF stays silent.

# Reproduction and accessibility

Fonts are local or embedded from the bundled files, whose upstream licenses are included. Every timeline is paused and seekable. Motion uses explicit from/to states and finite repeats. Keep copy in place long enough to read and preserve contrast against the dark canvas. Checks cover the assembled scenes at early, middle, and late proof times. Regenerate base screenshots from widget tests when the UI changes, then check alignment of the composition's overlays.
