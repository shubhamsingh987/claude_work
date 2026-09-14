# PiWalkTalk — landing page / store

Single-page, static storefront for PiWalkTalk (₹2999/pair). No build step, no
dependencies — plain HTML/CSS/JS. Ordering is WhatsApp-only: every CTA button
opens a chat to `+91 98846 25747` with a pre-filled message (see `js/main.js`).

## Deploy to Vercel

**Option A — dashboard (no CLI needed)**

1. Go to https://vercel.com/new
2. Choose "Deploy" without connecting a Git repo — drag and drop this folder
   (or the zip, unzipped) onto the import screen.
3. Framework preset: leave as **Other** — it's static, no build command needed.
4. Deploy.

**Option B — CLI**

```bash
npm i -g vercel
cd piwalktalk-store
vercel
```

Follow the prompts (link or create a project). Run `vercel --prod` to push to
production once you're happy with the preview URL.

**Option C — connect a Git repo**

Push this folder to a GitHub/GitLab/Bitbucket repo, then import it at
https://vercel.com/new — Vercel will detect it as a static site automatically.

## Editing

- `index.html` — all copy and page structure, one file.
- `css/style.css` — theme colors are CSS variables at the top (`--accent`,
  `--whatsapp`, etc.) — change once, applies everywhere.
- `js/main.js` — WhatsApp number and pre-filled messages live here
  (`WHATSAPP_NUMBER`, `DEFAULT_MESSAGE`). No other JS on the page.

## Before you go live

- [ ] Confirm the WhatsApp number in `js/main.js` (`WHATSAPP_NUMBER`) is correct
      and that WhatsApp Business (or a saved reply) is set up on that number —
      every button on the page will send buyers there.
- [ ] Swap in real product photos if/when you have them (currently
      illustration-only — see the inline SVGs in `index.html`).
- [ ] Double check the price (`₹2999`) and range claim (`~100m open air`)
      still match what you're actually shipping.
- [ ] Buy/point a custom domain in the Vercel dashboard if you don't want the
      default `*.vercel.app` URL.
