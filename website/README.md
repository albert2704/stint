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

Only this website folder is uploaded. The project uses CLI deployments. If enabling Git deployment later, first commit this folder and set the Vercel Root Directory to `website`.

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
