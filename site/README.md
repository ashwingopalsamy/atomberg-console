# Site

The project site, <https://apps.ashwingopalsamy.in/atomberg-console/>. One screen for people, plain pages and
machine-readable mirrors for search engines and agents.

```sh
cd site
npm ci
npm run dev        # sync docs, then astro dev
npm run build      # sync, build, markdown mirrors, sitemap, llms files, share cards
npm run deploy     # build, then wrangler deploy the app Worker and the hub Worker
```

- **Content** comes from the repository: `docs/*.md`, `docs/faq.json`, `CHANGELOG.md`. `scripts/sync.mjs` turns
  them into pages and `src/generated/knowledge.json`. Edit the sources, not the generated pages.
- **`worker/`** serves the build, a read-only MCP endpoint at `/mcp`, Markdown for `Accept: text/markdown`, and
  the security headers. `src/mcp-core.ts` holds the six tools; the browser registers the same ones through
  WebMCP when `navigator.modelContext` exists.
- **`hub/`** owns the hostname root (robots, sitemap index, llms index, well-known) and forwards
  `/atomberg-console/*` to the app Worker over a service binding. Adding an app is one entry in `hub/apps.json`.
- **Mirror**: `MIRROR=1 npm run build` produces the GitHub Pages copy. Same base path, `noindex`, canonical
  pointing at the apps URL. `.github/workflows/site.yml` does this.
- **No analytics, no third-party requests.** Fonts are self-hosted and the CSP says `script-src 'self'`.
