# steadfast launch

The launch film, the website at [steadfast.kartikkabadi.com](https://steadfast.kartikkabadi.com), and the README collages.

```
launch/
  video/     the film, in Remotion
  site/      the website, published as-is (no build step)
  collage/   the README collages, as HTML
  scripts/   renders the app screenshots and the collages
  worker.js  serves the film's byte ranges (Safari needs them)
  wrangler.toml
```

Every screen in the film, on the site, and in the collages comes from the real app. The film rebuilds the UI from `Sources/SteadfastApp`: palette, type scale, radii, strings and layout. The site and collages use renders of the SwiftUI views themselves.

## film

A 55-second 1920×1080 film at 60 fps.

```sh
cd launch/video
npm install
npm run dev                           # Remotion Studio: preview and scrub
npx remotion render Launch out/steadfast-launch.mp4 --codec=h264 --crf=16 --x264-preset=slow --audio-codec=aac --audio-bitrate=320k
npx remotion still OgCard ../site/assets/og.png    # also: Plate, Poster
npm run lint
```

- `scripts/compose.py` synthesises the original soundtrack and the sound effects. It needs numpy and scipy. The soundtrack runs at 120 BPM: cold open, riser, silence, drop, breakdown, build, drop, sting. The `rm-*` effects come from [remotion.media](https://remotion.media), peak-normalised and trimmed of leading silence.
- `scripts/export-assets.swift` exports the SF Symbols and app icons the film uses into `public/img`.
- `src/effects/grain-field.ts` is the light-sweep shader, written with `createEffect()`. The site runs the same GLSL live in its hero.
- `src/mix.ts` dips the music under every UI sound.
- Remotion's agent skills install with `npx skills add remotion-dev/skills`, pinned in `skills-lock.json`.

In headless Chrome on macOS, `system-ui` resolves to SF Pro, but `-apple-system` falls back to Times.

## screenshots and collages

```sh
launch/scripts/render-screens.sh     # site/assets/ui
launch/scripts/render-collages.sh    # docs/images
```

`render-screens.sh` compiles a copy of `scripts/check-ui.swift` beside the app's sources, with the film's story swapped in: "Ship my app", five websites, two hours. It then renders and crops each screen. The app's own sources are untouched.

The four renders that print a clock time (ends at, unlocks at) start early in a minute, so they always agree. The windows are 800 pt wide. At that width, the app lays out the onboarding wordmark clear of the traffic lights.

`render-collages.sh` photographs `collage/*.html` with headless Chrome at 2×.

## site

Preview it locally with the production headers:

```sh
cd launch && npx wrangler dev
```

Re-encode the film for the page after each render:

```sh
ffmpeg -i video/out/steadfast-launch.mp4 -c:v libx264 -crf 24 -preset slow -pix_fmt yuv420p \
  -c:a aac -b:a 160k -movflags +faststart site/assets/steadfast-launch.mp4
```

### deploy

The site is a Cloudflare Worker serving static assets. It answers only on `steadfast.kartikkabadi.com`: there is no `workers.dev` address and there are no preview URLs. Wrangler creates the custom domain's DNS record and certificate.

```sh
cd launch && CLOUDFLARE_ACCOUNT_ID=<account that owns kartikkabadi.com> npx wrangler deploy
```

- `site/_headers` sets a strict Content-Security-Policy. There are no third-party requests, and inline script is forbidden. It also sets HSTS, `nosniff`, frame denial, and a referrer and permissions policy.
- `Cache-Control: no-transform` keeps Cloudflare from rewriting the HTML. That stops the zone's automatic Web Analytics beacon, so the page carries no analytics.
- Static assets on Workers ignore `Range` headers, and Safari won't play video without them. `worker.js` runs only for `/assets/*.mp4` and returns `206 Partial Content`.
