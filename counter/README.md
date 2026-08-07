# Download counter

The number under the download buttons. Both routes are optional — with neither
configured the element stays hidden and the page makes no extra requests.

## Route 1 — GitHub Releases (recommended, no backend)

If the `.dmg` and `.zip` live on GitHub Releases, GitHub already counts every
completed download. Set one line in `Website/app.js`:

```js
var GITHUB_REPO = "yourname/funnotch";
```

- Counts finished transfers, not clicks.
- Sums every asset of every release, so old versions still count.
- Nothing to deploy, nothing to pay for, and nobody can inflate it.
- The repo must be public. It does **not** have to contain the source — a repo
  holding only a README and the releases works.

Unauthenticated GitHub API calls are limited to 60 per hour per visitor IP.
Past that the request fails and the counter hides itself, which is the correct
outcome for a decoration.

## Route 2 — the Worker (when the files aren't on GitHub)

`worker.js` counts button clicks instead. Looser — a click is not a download —
but it works with the binaries served from the site itself.

1. Create a KV namespace:

```bash
npx wrangler kv namespace create COUNTER
```

2. Put the id it prints into `wrangler.toml`:

```toml
name = "funnotch-downloads"
main = "worker.js"
compatibility_date = "2026-08-03"

[[kv_namespaces]]
binding = "COUNTER"
id = "<the id from step 1>"
```

3. Edit `ALLOWED_ORIGINS` at the top of `worker.js` to your real domain. Only
   those origins may increment; reads are open to anyone.

4. Deploy:

```bash
npx wrangler deploy
```

5. Put the URL it prints into `Website/app.js`:

```js
var COUNTER_API = "https://funnotch-downloads.<your-subdomain>.workers.dev";
```

### Worth knowing

- **Free-tier KV allows 1000 writes a day.** A counted click costs two (the
  total and the per-visitor marker), so roughly 500 downloads a day before
  writes start failing. Reads are effectively unlimited.
- **Increments are read-add-write, not atomic.** Two clicks in the same instant
  can produce one increment. Fine for this; a Durable Object is the fix if it
  ever isn't.
- **The count is deliberately hidden below 1**, so a fresh deploy shows nothing
  rather than "0 downloads so far".

## Resetting

```bash
npx wrangler kv key put --binding COUNTER downloads 0 --remote
```
