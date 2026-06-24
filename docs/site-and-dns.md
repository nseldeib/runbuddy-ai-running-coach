# Otterpace site + API — deploy on Vercel (otterpace.com)

The marketing landing page and privacy policy live in `site/` (`index.html`,
`privacy.html`, `style.css`, `otterpace-icon.png`) and the AI coach API lives in
`api/` (`coach.ts`). Both deploy together on **Vercel** — one project serves the
static site at `otterpace.com` and the function at `otterpace.com/api/coach`.
The privacy policy URL the app + App Store reference is
**https://otterpace.com/privacy** (also `/privacy.html`).

> GitHub Pages was retired in favor of Vercel because the coach API needs a
> serverless backend Pages can't host. Keeping one host avoids splitting the
> site and API across two platforms (and the DNS conflict that creates).

## One-time setup (you)

### 1. Import the repo into Vercel
Vercel → **Add New… → Project** → import `nseldeib/otterpace`. Framework preset:
**Other**. Vercel auto-detects `vercel.json` (static site served from `site/`)
and the `api/` serverless function. Deploy.

### 2. Add the domain
Vercel project → **Settings → Domains** → add `otterpace.com` (and `www`). Vercel
shows the exact DNS records to set. On **Namecheap → Domain List → Manage
otterpace.com → Advanced DNS**, add what Vercel specifies — typically:

| Type  | Host | Value                  |
|-------|------|------------------------|
| A     | @    | 76.76.21.21            |
| CNAME | www  | cname.vercel-dns.com.  |

(Use whatever Vercel's Domains tab shows — it's authoritative.) Remove any
default Namecheap "parking"/redirect records on `@` and `www` first. DNS can take
30 min–24 h to propagate; Vercel issues HTTPS automatically once it resolves.

### 3. (optional) Coach model override
The coach uses `claude-opus-4-8` by default. To change it, set the env var
**`COACH_MODEL`** in the Vercel project. No server-side API key is needed — keys
are bring-your-own, sent per request from the app (see `docs/ai-coach.md`).

## Verify
- `https://otterpace.com` and `https://otterpace.com/privacy` load.
- `https://otterpace.com/api/coach` returns **405** to a plain GET (it's POST-only)
  — a quick liveness check for the function.

## Email (optional, for the privacy contact)
`hello@otterpace.com` is referenced in the privacy policy + Code of Conduct. Set
up an alias/forwarding for it on Namecheap (or your mail provider) when ready.
