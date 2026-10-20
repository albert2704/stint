# Stint website

Live site: https://stint-focus.vercel.app

This is the single page marketing website from spec 0009. It uses plain HTML, CSS, and a small illustration countdown. No build step or package installation is needed.

## Local preview

From this directory:

```sh
python3 -m http.server 4179 --bind 127.0.0.1
```

Open http://127.0.0.1:4179. The site follows the system appearance until a visitor chooses light or dark with the header toggle. That choice is saved locally in the browser. Motion follows the system reduced motion preference. FAQ disclosures and all links work without JavaScript.

## Deploy

The local `.vercel` directory links this folder to the `stint-focus` project in `nguyen-viets-projects`. Deploy from this folder:

```sh
npx vercel deploy --prod
```

Only this website folder is uploaded. The project uses CLI deployments. If enabling Git deployment later, set the Vercel Root Directory to `website`.

## Editing

- `index.html` preserves the supplied reference composition and contains the public release, license, privacy, and contact links.
- `styles.css` owns the dark and light tokens, local font faces, responsive rules, and reduced motion behavior.
- `theme.js` applies the saved appearance before the page paints and makes the header toggle accessible by keyboard.
- `script.js` updates only the decorative countdown and cycle fill. It does not play audio or save data.
- `assets/fonts/` contains Hanken Grotesk and Martian Mono with their OFL notices. Hanken 700 is used instead of the unbundled 800 weight, as allowed by the spec.
- `og-image.png` is the 1200 by 630 social sharing image.

When publishing a new app release, update the DMG URL, displayed version and file size, compatibility notes, and first launch instructions. Keep the preview disclosure until the linked download has a Developer ID signature and Apple notarization.

The local `qa/` fixtures force each palette and reduced motion for visual inspection. They are excluded from Git and Vercel deployment. The production page starts from system preferences and supports a saved manual choice.

Validation during delivery covered desktop and phone layouts down to 320 CSS pixels, dark and light palettes, keyboard FAQ activation, sticky anchor offsets, reduced motion styles, countdown updates, release availability, and public HTTPS access. No browser console errors were observed. Safari, Firefox, and a screen reader have not been separately tested.

## Current app release

The download links target Stint **0.3.0 Beta 1**, a universal DMG for macOS 12 or later. The page describes the five additions: saved focus profiles, a Flow count up timer, independent ambient layers, weekly focus targets, and the optional Pick up here sentence. The verified DMG is 33,942,029 bytes, displayed as 33.9 MB.

The hero’s countdown and existing timer illustrations continue to demonstrate Pomodoro. The Sound illustration includes example ambient levels; these are decorative examples, not controls or evidence of app playback. The page uses the existing fonts, palettes, responsive grids and reduced motion rules.

The blocker FAQ distinguishes the live Edge checks performed for 0.2.0 from 0.3.0, whose real browser enforcement has not been re-tested. Chrome, physical Intel hardware and macOS 12 remain unverified. The release remains ad hoc signed and not notarized; its first launch guidance and disclosures are retained. Publishing the GitHub release and deploying this folder are separate steps.

The previous blocker website update was checked in dark and light themes at desktop and phone sizes, including 320, 390, 780 and 1440 CSS pixels. No horizontal overflow or browser console errors were observed. Keyboard activation opened the setup FAQ, and the download and documentation links point to the current beta. The existing reduced motion rules also apply to the new section.

The 0.3.0 update passed local Chromium checks at 320, 390, 780 and 1440 CSS pixels in both themes: no horizontal or feature-card overflow, valid in-page anchors, unique IDs, working keyboard FAQ activation, saved theme selection, and reduced motion. No browser console errors were observed. Download URLs target the new release; public asset availability is checked after publication, separately from these local layout checks.
