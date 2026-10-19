// Writes the hub's root from apps.json: the page and its Markdown mirror, the llms, sitemap and well-known files, the icon
// set and the share card. Adding an app is one JSON entry (plus a service binding if it is hosted here); nothing here names an app.
// satori, resvg and Geist come from the project site's node_modules, so run it through `npm run deploy` there.
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import satori from "satori";
import { Resvg } from "@resvg/resvg-js";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "public");
const { host, site, owner, apps } = JSON.parse(readFileSync(join(here, "apps.json"), "utf8"));
const origin = `https://${host}`;
const url = `${origin}/`;
const today = new Date().toISOString().slice(0, 10);
const write = (name, data) => {
  mkdirSync(dirname(join(out, name)), { recursive: true });
  writeFileSync(join(out, name), data);
};
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const siteName = `Apps by ${owner.name}`;
const [head1, head2] = site.headline;
// An app with a url lives on its own host; one without is served here at /<slug>/. A sitemap index can only list its own
// host, and the MCP card and Worker route exist only for hosted apps, so those use hostedApps.
const appUrl = (a) => a.url ?? `${origin}/${a.slug}/`;
const appId = (a) => `${appUrl(a)}#app`;
const llmsUrl = (a) => {
  if (!a.url) return `${origin}/${a.slug}/llms.txt`;
  // An external site is linked at its llms.txt only when it publishes one; otherwise the link is the site itself.
  return a.llms === true ? `${a.url}llms.txt` : a.url;
};
const hostedApps = apps.filter((a) => !a.url);
const ogImage = `${origin}/og/home.png`;
const personId = `${owner.url}/#person`; // the id the app pages use too, so the author is one entity across the site
const xLink = owner.links.find((l) => /^(www\.)?(x|twitter)\.com$/.test(new URL(l.url).hostname));
const xHandle = xLink ? `@${new URL(xLink.url).pathname.split("/").filter(Boolean)[0]}` : null;

// ---------------------------------------------------------------- crawlers and agents

const bots = ["GPTBot", "OAI-SearchBot", "ChatGPT-User", "ClaudeBot", "Claude-User", "Claude-SearchBot", "PerplexityBot", "Perplexity-User", "Google-Extended", "Applebot-Extended", "CCBot"];
write(
  "robots.txt",
  `User-agent: *\nAllow: /\n\n${bots.map((b) => `User-agent: ${b}\nAllow: /\n`).join("\n")}\nSitemap: ${origin}/sitemap.xml\n`,
);
write(
  "sitemap.xml",
  `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n  <sitemap><loc>${origin}/sitemap-pages.xml</loc><lastmod>${today}</lastmod></sitemap>\n${hostedApps
    .map((a) => `  <sitemap><loc>${origin}/${a.slug}/sitemap.xml</loc></sitemap>`)
    .join("\n")}\n</sitemapindex>\n`,
);
write(
  "sitemap-pages.xml",
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n  <url><loc>${url}</loc><lastmod>${today}</lastmod></url>\n</urlset>\n`,
);

const appLines = (link) => apps.map((a) => `- [${a.name}](${link(a)}): ${a.description}`).join("\n");
const sources = apps.filter((a) => a.repo).map((a) => `- [${a.name} source](${a.repo})`).join("\n");
const authorLines = owner.links.map((l) => `- [${l.label}](${l.url})`).join("\n");

write(
  "llms.txt",
  `# ${siteName}\n\n> ${site.description}\n\nHosted apps have their own llms.txt and Markdown pages; sites on other hosts are linked directly.\n\n## Apps\n${appLines(llmsUrl)}\n\n## Source\n${sources}\n\n## Author\n- [${owner.name}](${owner.url}): ${owner.tagline}.\n\n## Optional\n- [This page as Markdown](${origin}/index.md)\n- [llms-full.txt](${origin}/llms-full.txt): everything above in one file.\n- [knowledge.json](${origin}/knowledge.json): the same facts as data.\n- [MCP cards](${origin}/.well-known/mcp.json): where each app's read-only MCP server lives.\n`,
);
const markdown = `# ${siteName}\n\n> ${site.description}\n\nCanonical: ${url}\n\n${site.headline.join(" ")}${site.lede ? ` ${site.lede}` : ""}\n\n## Apps\n${appLines(appUrl)}\n\n## Source\n${sources}\n\n## Author\n${owner.name}: ${owner.tagline}.\n\n${authorLines}\n`;
write("index.md", markdown);
write(
  "llms-full.txt",
  `# ${siteName}\n\n> ${site.description}\n\n${apps
    .map((a) => {
      const lines = [`- Site: ${appUrl(a)}`, a.repo && `- Source: ${a.repo}`, `- llms.txt: ${llmsUrl(a)}`];
      // Only hosted apps have llms-full.txt and Markdown pages under this host.
      if (!a.url) lines.push(`- llms-full.txt: ${origin}/${a.slug}/llms-full.txt`, `- Markdown: ${origin}/${a.slug}/index.md`);
      return `## ${a.name}\n\n${a.description}\n\n${lines.filter(Boolean).join("\n")}\n`;
    })
    .join("\n")}\n## Author\n\n${owner.name}, ${owner.tagline}.\n\n${authorLines}\n`,
);
write(
  "knowledge.json",
  JSON.stringify({
    name: siteName,
    url,
    description: site.description,
    updated: today,
    author: { name: owner.name, url: owner.url, tagline: owner.tagline, links: owner.links },
    apps: apps.map((a) => ({
      slug: a.slug,
      name: a.name,
      description: a.description,
      url: appUrl(a),
      source: a.repo,
      llms: llmsUrl(a),
      // Only hosted apps have these pages under this host.
      ...(a.url ? {} : { llmsFull: `${origin}/${a.slug}/llms-full.txt`, markdown: `${origin}/${a.slug}/index.md`, mcpCard: `${origin}/${a.slug}/.well-known/mcp.json` }),
    })),
  }),
);
write(
  "ai.txt",
  `# ${siteName}: how automated readers may use this site\n# ${url}\n\nSearch engines, answer engines and agents may read, quote and cite these pages.\nPlease link to the page you used.\n\nProse:   CC BY 4.0 (attribution required).\nCode:    each app states its own license in its repository.\n\nMachine-readable:\n  /llms.txt\n  /llms-full.txt\n  /index.md\n  /knowledge.json\n  /.well-known/mcp.json  (where each app's read-only MCP card lives)\n  Accept: text/markdown on / returns Markdown.\n`,
);
write(
  ".well-known/mcp.json",
  JSON.stringify(
    {
      name: "apps-hub",
      title: siteName,
      description: "Index of the read-only MCP servers the apps here publish. Each card describes one server.",
      servers: hostedApps.map((a) => ({ name: a.name, card: `${origin}/${a.slug}/.well-known/mcp.json` })),
    },
    null,
    2,
  ) + "\n",
);
// Contact is the first repo listed: a security.txt without one is not valid.
const contactRepo = apps.find((a) => a.repo)?.repo;
if (!contactRepo) throw new Error("apps.json: no app has a repo, so security.txt has no Contact");
write(
  ".well-known/security.txt",
  `Contact: ${contactRepo}/security/advisories/new\nExpires: 2027-10-11T00:00:00.000Z\nPreferred-Languages: en\nCanonical: ${origin}/.well-known/security.txt\n`,
);
write("humans.txt", `${siteName}\nMade by ${owner.name}, ${owner.url}\nType: the system font stack. Icons: Lucide (ISC), and Tabler (MIT) for the X mark.\n`);

// ---------------------------------------------------------------- icons

// A checkbox whose tick overshoots it, in highlighter yellow on the dark tile the apps use: the page is a list of things
// crossed off. The small variant thickens the strokes so it still reads at 16px.
const INK = "#0e0f10";
const PAPER = "#f5f5f7";
const MARK = "#c9ff2f";
const mark = ({ rx = 116, scale = 1, stroke = 30 } = {}) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="${rx}" fill="${INK}"/><g transform="translate(256 256) scale(${scale}) translate(-256 -256)" fill="none" stroke-linecap="round" stroke-linejoin="round"><rect x="128" y="140" width="228" height="228" rx="64" stroke="${PAPER}" stroke-width="${stroke}"/><path d="M180 270l62 62L392 148" stroke="${MARK}" stroke-width="${stroke + 14}"/></g></svg>`;
const png = (svg, size) => new Resvg(svg, { fitTo: { mode: "width", value: size } }).render().asPng();
const small = mark({ scale: 1.18, stroke: 38 });
const ico = (entries) => {
  const head = Buffer.alloc(6);
  head.writeUInt16LE(1, 2);
  head.writeUInt16LE(entries.length, 4);
  let offset = 6 + 16 * entries.length;
  const dir = entries.map(({ size, data }) => {
    const e = Buffer.alloc(16);
    e[0] = size;
    e[1] = size;
    e.writeUInt16LE(1, 4);
    e.writeUInt16LE(32, 6);
    e.writeUInt32LE(data.length, 8);
    e.writeUInt32LE(offset, 12);
    offset += data.length;
    return e;
  });
  return Buffer.concat([head, ...dir, ...entries.map((e) => e.data)]);
};
write("favicon.svg", small);
write("favicon.ico", ico([16, 32, 48].map((size) => ({ size, data: png(small, size) }))));
write("icon-192.png", png(mark(), 192));
write("icon-512.png", png(mark(), 512));
write("apple-touch-icon.png", png(mark({ rx: 0, scale: 1.1 }), 180)); // iOS rounds it itself
// Geist, self-hosted: the CSP allows font-src 'self' and nothing else.
write("fonts/geist-latin-wght-normal.woff2", readFileSync(join(here, "..", "node_modules", "@fontsource-variable", "geist", "files", "geist-latin-wght-normal.woff2")));
// Icons for external apps are checked in beside this script: their repos are elsewhere, and the build fetches nothing.
for (const name of readdirSync(join(here, "icons")).filter((f) => !f.startsWith("."))) {
  write(`icons/${name}`, readFileSync(join(here, "icons", name)));
}
write(
  "manifest.webmanifest",
  JSON.stringify({
    name: siteName,
    short_name: "Apps",
    description: site.description,
    id: "/",
    start_url: "/",
    scope: "/",
    display: "browser",
    background_color: INK,
    theme_color: INK,
    icons: [
      { src: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
  }) + "\n",
);

// The project site already carries the avatar. It is served for the Person entity and inlined into the page, since the
// CSP allows data: images and it saves a request.
const pfpFile = readFileSync(join(here, "..", "public", "brand", "pfp.jpg"));
write("pfp.jpg", pfpFile);
const pfp = `data:image/jpeg;base64,${pfpFile.toString("base64")}`;

// ---------------------------------------------------------------- share card

const font = (weight) => readFileSync(join(here, "..", "node_modules", "@fontsource", "geist-sans", "files", `geist-sans-latin-${weight}-normal.woff`));
const el = (type, style, children) => ({ type, props: { style, children } });
const row = (style, children) => el("div", { display: "flex", ...style }, children);
const card = row({ width: 1056, height: 486, background: "#0a0b0d", padding: 72, flexDirection: "column", justifyContent: "space-between", fontFamily: "Geist" }, [
  row({ alignItems: "center", gap: 20 }, [
    { type: "img", props: { src: `data:image/png;base64,${png(mark(), 128).toString("base64")}`, width: 64, height: 64 } },
    el("div", { display: "flex", fontSize: 30, fontWeight: 600, color: "#f5f5f7", letterSpacing: -0.5 }, siteName),
  ]),
  el("div", { display: "flex", flexDirection: "column", fontSize: 104, fontWeight: 600, letterSpacing: -5, lineHeight: 0.98 }, [
    el("div", { display: "flex", color: "#f5f5f7" }, head1),
    el("div", { display: "flex", color: MARK }, head2),
  ]),
  row({ justifyContent: "space-between", alignItems: "center" }, [
    el("div", { display: "flex", padding: "10px 24px", borderRadius: 999, background: MARK, color: "#171512", fontSize: 26, fontWeight: 600 }, `${apps.length} so far`),
    el("div", { display: "flex", fontSize: 24, color: "#5e5e68" }, host),
  ]),
]);
const fonts = [
  { name: "Geist", data: font(400), weight: 400, style: "normal" },
  { name: "Geist", data: font(600), weight: 600, style: "normal" },
];
write("og/home.png", new Resvg(await satori(card, { width: 1200, height: 630, fonts }), { fitTo: { mode: "width", value: 1200 } }).render().asPng());

// ---------------------------------------------------------------- page

// Icons are Lucide (ISC), except X: Lucide has no X mark, so that one is Tabler's brand-x, which shares Lucide's stroke style.
// Classes mark the part of each icon that moves on hover.
const svg = (inner) =>
  `<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${inner}</svg>`;
const icons = {
  website: svg(`<circle cx="12" cy="12" r="10"/><path class="meridian" d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>`),
  github: svg(
    `<path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4"/><path class="tail" d="M9 18c-4.51 2-5-2-7-2"/>`,
  ),
  linkedin: svg(
    `<path d="M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-2-2 2 2 0 0 0-2 2v7h-4v-7a6 6 0 0 1 6-6z"/><rect width="4" height="12" x="2" y="9"/><circle class="dot" cx="4" cy="4" r="2"/>`,
  ),
  x: svg(`<path d="M4 4l11.733 16h4.267l-11.733 -16z"/><path class="slash" pathLength="1" d="M4 20l6.768 -6.768m2.46 -2.46l6.772 -6.772"/>`),
};
const goIcon = (inner) => `<svg class="go" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${inner}</svg>`;
const arrow = goIcon(`<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>`);
// Lucide arrow-up-right. An external card opens in a new tab, so its arrow points out of the box, not along the row.
const outArrow = goIcon(`<path d="M7 7h10v10"/><path d="M7 17 17 7"/>`);

// The page is a done-list. Each app is a row: the annoyance it fixed, crossed off as the row scrolls in or is hovered,
// beside the app that fixed it. Rows group by kind and the chips filter the groups with :has(), so there is no script.
// External apps leave the hub: they open in a new tab and their arrow points out.
const GROUPS = {
  macos: ["mac", "On your Mac", "Mac"],
  editor: ["editor", "In your editor", "Editor"],
  webapp: ["web", "On the web", "Web"],
  website: ["web", "On the web", "Web"],
};
const groupOf = (a) => {
  const g = GROUPS[a.kind];
  if (!g) throw new Error(`apps.json: unknown kind "${a.kind}" for "${a.slug}"`);
  return { id: g[0], label: g[1], chip: g[2] };
};
const order = [];
for (const a of apps) {
  const g = groupOf(a);
  if (!order.some((o) => o.id === g.id)) order.push(g);
}
const tick = `<span class="tick" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"><path pathLength="1" d="M5 12.5l4.5 4.5L19 7.5"/></svg></span>`;
let seq = 0; // entrance order
const rowOf = (a) => {
  const external = Boolean(a.url);
  const href = a.url ?? `/${a.slug}/`;
  const src = a.icon ?? `/${a.slug}/icon-192.png`;
  return `<a class="row" href="${esc(href)}"${external ? ` target="_blank" rel="noopener"` : ""} style="--i:${seq++}">${tick}<span class="said"><span class="line">${esc(a.annoyance ?? a.name)}</span><span class="more"><span>${esc(a.description)}</span></span></span><span class="fix"><img class="ico" src="${esc(src)}" alt="" width="34" height="34"><b>${esc(a.name)}</b>${external ? outArrow : arrow}${external ? `<span class="sr"> (opens in a new tab)</span>` : ""}</span></a>`;
};
const groupsHtml = order
  .map((g) => {
    const list = apps.filter((a) => groupOf(a).id === g.id);
    return `<section class="group" data-g="${g.id}"><div class="gin"><h2 class="gl"><span>${esc(g.label)}</span><i>${list.length}</i></h2><div class="rows">${list.map(rowOf).join("")}</div></div></section>`;
  })
  .join("");
// The last row is unchecked on purpose: the list is not finished.
const nextHtml = site.next
  ? `<section class="group tail"><div class="gin"><span class="gl"></span><div class="rows"><div class="row next" style="--i:${seq}"><span class="tick" aria-hidden="true"></span><span class="said"><span class="line">${esc(site.next)}</span></span></div></div></div></section>`
  : "";
const filters = `<fieldset class="filters" style="--i:${apps.length}"><legend class="sr">Show</legend>${[{ id: "all", chip: "All", n: apps.length }, ...order.map((g) => ({ id: g.id, chip: g.chip, n: apps.filter((a) => groupOf(a).id === g.id).length }))]
  .map((c, i) => `<input type="radio" name="f" id="f-${c.id}"${i === 0 ? " checked" : ""}><label for="f-${c.id}">${esc(c.chip)}<i>${c.n}</i></label>`)
  .join("")}</fieldset>`;
// A group collapses (and fades) when another chip is chosen; the unchecked row only shows under "All".
const gone = [...order.map((g) => `body:has(#f-${g.id}:checked) .group:not([data-g="${g.id}"])`), `body:has(.filters input:not(#f-all):checked) .group.tail`].join(",");

const links = owner.links
  .map((l) => {
    const icon = icons[l.label.toLowerCase()];
    if (!icon) throw new Error(`apps.json: no icon for owner link "${l.label}"`);
    return `<a href="${esc(l.url)}" target="_blank" rel="me noopener" aria-label="${esc(l.label)}" data-label="${esc(l.label)}">${icon}</a>`;
  })
  .join("");

const css = `
@font-face{font-family:"Geist";src:url(/fonts/geist-latin-wght-normal.woff2) format("woff2");font-weight:100 900;font-style:normal;font-display:swap}
/* Two registered numbers drive every "crossed off" effect: --scroll is animated by a timeline, --hover by the pointer.
   Registering them lets --hover transition and lets one value feed the strike, the tick and the marker. */
@property --scroll{syntax:"<number>";inherits:true;initial-value:0}
@property --hover{syntax:"<number>";inherits:true;initial-value:0}
:root{color-scheme:light dark;--bg:#fafbfc;--ink:#0a0c10;--muted:#5a6272;--line:rgba(10,12,16,.12);--mark:#c9ff2f;--mark-fill:#c9ff2f;--accent:#2f54ff}
@media (prefers-color-scheme:dark){:root{--bg:#0a0b0d;--ink:#eef1f6;--muted:#8d95a5;--line:rgba(238,241,246,.14);--mark:#c9ff2f;--mark-fill:rgba(201,255,47,.42);--accent:#7a93ff}}
*{box-sizing:border-box}
html{background:var(--bg)}
body{margin:0;color:var(--ink);font:400 1rem/1.5 "Geist",ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}
::selection{background:var(--mark);color:#0a0c10}
a{color:inherit;text-decoration:none}
a:focus-visible{outline:2px solid var(--accent);outline-offset:4px;border-radius:10px}
main{width:min(100%,880px);margin-inline:auto;padding:clamp(18px,2.4vw,26px) clamp(18px,4vw,36px) 56px}
.sr{position:absolute;width:1px;height:1px;margin:-1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
@keyframes rise{from{opacity:0;transform:translateY(12px)}}

.top{display:flex;align-items:center;justify-content:space-between;gap:16px;animation:rise .7s cubic-bezier(.16,1,.3,1) backwards}
.who{display:flex;align-items:center;gap:10px;font-size:.9rem;font-weight:600;letter-spacing:-.01em}
.who img{display:block;width:30px;height:30px;border-radius:50%;object-fit:cover;box-shadow:0 0 0 1px var(--line);transition:transform .6s cubic-bezier(.34,1.56,.64,1)}
.who:hover img{transform:rotate(-8deg) scale(1.1)}

.hero{position:relative;margin-top:clamp(32px,6vh,60px)}
h1{margin:0;font-size:clamp(2.3rem,6.4vw,4.4rem);font-weight:660;line-height:.92;letter-spacing:-.058em}
h1 .l{display:block;animation:rise .9s cubic-bezier(.16,1,.3,1) backwards}
h1 .l + .l{animation-delay:.12s}
/* The highlighter: a skewed block that swipes in behind the lower half of the word, like a pen across a printed line.
   The word turns dark with the swipe so it reads on the marker in both themes. */
h1 mark{position:relative;z-index:0;display:inline-block;padding-inline:.03em;color:var(--ink);background:none;animation:ink .4s .8s both}
@keyframes ink{to{color:#0a0c10}}
h1 mark::before{content:"";position:absolute;z-index:-1;inset:.4em -.07em .02em -.07em;background:var(--mark);border-radius:.04em;transform:skew(-5deg) scaleX(0);transform-origin:0 50%;animation:swipe .85s .55s cubic-bezier(.65,0,.35,1) forwards}
@keyframes swipe{to{transform:skew(-5deg) scaleX(1)}}
/* On a dark page the word is dark ink, so the block covers the whole word, not just its lower half. */
@media (prefers-color-scheme:dark){h1 mark::before{inset:.07em -.07em -.01em -.07em}}
/* The sticker is generated content on the second line, so it sits right after the word and stays out of the heading text. */
h1 .l[data-sticker]::after{content:attr(data-sticker);display:inline-block;vertical-align:top;margin:.5em 0 0 .7em;padding:.45em .9em;border-radius:999px;background:var(--mark);color:#0a0c10;font-size:clamp(.78rem,1.1vw,.92rem);font-weight:650;letter-spacing:-.01em;line-height:1.15;white-space:nowrap;box-shadow:0 2px 0 rgba(0,0,0,.16);transform:rotate(-6deg);animation:sticker .8s .95s cubic-bezier(.34,1.56,.64,1) backwards;transition:transform .45s cubic-bezier(.34,1.56,.64,1)}
h1 .l[data-sticker]:hover::after{transform:rotate(3deg) scale(1.07)}
@keyframes sticker{from{opacity:0;transform:rotate(-34deg) scale(.2)}}

.filters{margin:clamp(22px,3.5vh,34px) 0 0;padding:0;border:0;display:flex;flex-wrap:wrap;gap:6px;animation:rise .7s .3s cubic-bezier(.16,1,.3,1) backwards}
.filters input{position:absolute;opacity:0;pointer-events:none}
.filters label{display:inline-flex;align-items:baseline;gap:.5em;padding:.45em .9em;border:1.5px solid var(--line);border-radius:999px;font-size:.85rem;font-weight:600;letter-spacing:-.01em;cursor:pointer;transition:background .25s,color .25s,border-color .25s,transform .35s cubic-bezier(.34,1.56,.64,1)}
.filters label i{font-style:normal;font-weight:500;color:var(--muted);transition:color .25s}
.filters label:hover{transform:translateY(-2px);border-color:var(--ink)}
.filters input:checked + label{background:var(--ink);border-color:var(--ink);color:var(--bg)}
.filters input:checked + label i{color:inherit;opacity:.6}
.filters input:focus-visible + label{outline:2px solid var(--accent);outline-offset:3px}

.groups{margin-top:16px;border-bottom:1px solid var(--line)}
.group{display:grid;grid-template-rows:1fr;transition:grid-template-rows .6s cubic-bezier(.16,1,.3,1),opacity .35s}
.gin{min-height:0;overflow:clip}
/* The label sticks to the top while its rows scroll under it, so the page always says which group you are in. */
.gl{position:sticky;top:0;z-index:2;display:flex;gap:.5em;align-items:baseline;margin:0;padding:16px 0 6px;background:var(--bg);font-size:.8rem;font-weight:600;letter-spacing:-.005em;color:var(--muted)}
.gl:empty{display:none}
.gl i{font-style:normal;font-weight:500;opacity:.7}
.rows{border-top:1px solid var(--line)}
.row + .row{border-top:1px solid var(--line)}
${gone}{grid-template-rows:0fr;opacity:0;visibility:hidden;transition:grid-template-rows .6s cubic-bezier(.16,1,.3,1),opacity .25s,visibility 0s .6s}

.row{--p:max(var(--scroll),var(--hover));position:relative;display:grid;grid-template-columns:26px minmax(0,1fr) auto;column-gap:clamp(12px,1.8vw,20px);align-items:center;padding:clamp(10px,1.1vw,13px) 0;transition:--hover .55s cubic-bezier(.65,0,.35,1),opacity .35s;animation:rise .8s cubic-bezier(.16,1,.3,1) backwards;animation-delay:calc(var(--i)*70ms + .35s)}
a.row:hover,a.row:focus-visible{--hover:1}
a.row:focus-visible{outline-offset:-4px;border-radius:12px}
.groups:has(a.row:hover) a.row:not(:hover){opacity:.36}

/* The checkbox fills and the tick draws as --p goes 0 to 1. */
.tick{display:grid;place-items:center;width:26px;height:26px;border:1.5px solid color-mix(in oklab,var(--ink) 38%,transparent);border-radius:8px;background:color-mix(in oklab,var(--ink) calc(var(--p)*100%),transparent);color:var(--bg)}
.tick svg{width:16px;height:16px}
.tick path{stroke-dasharray:1;stroke-dashoffset:calc(1 - var(--p))}
.next .tick{border-style:dashed}

.said{min-width:0;font-size:clamp(1rem,1.5vw,1.15rem);font-weight:540;line-height:1.2;letter-spacing:-.022em}
.line{background:linear-gradient(currentColor,currentColor) no-repeat 0 58%/calc(var(--p)*100%) max(.07em,1.5px);-webkit-box-decoration-break:clone;box-decoration-break:clone;color:color-mix(in oklab,var(--ink),var(--muted) calc(var(--p)*100%))}
.more{display:grid;grid-template-rows:0fr;transition:grid-template-rows .45s cubic-bezier(.16,1,.3,1)}
.more > span{min-height:0;overflow:hidden;padding-top:0;max-width:52ch;font-size:.9rem;font-weight:400;letter-spacing:0;line-height:1.45;color:var(--muted);transition:padding-top .45s cubic-bezier(.16,1,.3,1)}
a.row:hover .more,a.row:focus-visible .more{grid-template-rows:1fr}
a.row:hover .more > span,a.row:focus-visible .more > span{padding-top:8px}

.fix{display:flex;align-items:center;gap:10px;padding-left:clamp(0px,1.6vw,18px)}
.ico{display:block;width:34px;height:34px;border-radius:9px;box-shadow:0 0 0 1px var(--line);transform:rotate(calc(var(--hover)*-6deg)) scale(calc(1 + var(--hover)*.1))}
.fix b{padding-inline:.18em;margin-inline:-.18em;font-size:.95rem;font-weight:650;letter-spacing:-.015em;white-space:nowrap;background:linear-gradient(var(--mark-fill),var(--mark-fill)) no-repeat 0 88%/calc(var(--p)*100%) .55em}
.go{flex:none;color:var(--muted);transform:translateX(calc(var(--hover)*4px));transition:color .2s}
a.row:hover .go,a.row:focus-visible .go{color:var(--ink)}

.next .line{color:var(--muted)}
.next .line::after{content:"";display:inline-block;width:.09em;height:.95em;margin-left:.12em;vertical-align:-.1em;background:var(--ink);animation:blink 1.1s steps(1) infinite}
@keyframes blink{50%{opacity:0}}

/* Bare icons, no boxes. The row dims around the one you are on; each icon does its own small thing. */
.links{display:flex;gap:2px;margin-right:-9px}
.links a{position:relative;display:grid;place-items:center;width:38px;height:38px;color:var(--muted);transition:color .2s,opacity .25s,transform .4s cubic-bezier(.34,1.56,.64,1)}
.links svg{width:20px;height:20px}
.links:hover a:not(:hover),.links:focus-within a:not(:focus-visible){opacity:.4}
.links a:hover,.links a:focus-visible{color:var(--ink);transform:translateY(-2px)}
.links a::after{content:attr(data-label);position:absolute;top:calc(100% - 2px);left:50%;transform:translate(-50%,-3px);font-size:.72rem;font-weight:500;letter-spacing:.01em;white-space:nowrap;color:var(--muted);opacity:0;pointer-events:none;transition:opacity .2s,transform .35s cubic-bezier(.16,1,.3,1)}
.links a:hover::after,.links a:focus-visible::after{opacity:1;transform:translate(-50%,0)}
.meridian,.dot{transform-box:fill-box;transform-origin:center}
.tail{transform-origin:9px 18px}
.slash{stroke-dasharray:1;stroke-dashoffset:0}
.links a:hover .meridian{animation:spin 1.1s cubic-bezier(.45,0,.2,1)}
.links a:hover .tail{animation:wag .9s ease-in-out}
.links a:hover .dot{animation:pop .6s cubic-bezier(.34,1.56,.64,1)}
.links a:hover .slash{animation:draw .6s cubic-bezier(.45,0,.2,1)}
@keyframes spin{50%{transform:scaleX(.05)}}
@keyframes wag{20%{transform:rotate(-20deg)}45%{transform:rotate(14deg)}70%{transform:rotate(-9deg)}}
@keyframes pop{40%{transform:scale(1.9)}70%{transform:scale(.85)}}
@keyframes draw{from{stroke-dashoffset:1}}

/* Crossing off. On a wide screen the whole list is in view, so it ticks itself off one row after another once the page has
   settled. On a phone the list is long, so a row is crossed off a little after it passes the middle of the screen. Where
   the scroll timeline is not supported a phone shows the rows already done, so a fix is never hidden. */
@keyframes cross{to{--scroll:1}}
@media (min-width:761px){
  .row:not(.next){animation:rise .8s cubic-bezier(.16,1,.3,1) backwards,cross .7s cubic-bezier(.65,0,.35,1) both;animation-delay:calc(var(--i)*70ms + .35s),calc(1.5s + var(--i)*.42s)}
}
@media (max-width:760px){
  @supports (animation-timeline:view()){
    .row:not(.next){animation:rise .8s cubic-bezier(.16,1,.3,1) backwards,cross linear both;animation-delay:calc(var(--i)*70ms + .35s),0s;animation-timeline:auto,view();animation-range:normal,cover 45% cover 62%}
  }
  @supports not (animation-timeline:view()){
    .row:not(.next){--scroll:1}
  }
}

@media (hover:none){.more{grid-template-rows:1fr}.more > span{padding-top:8px}.links a::after{display:none}}
@media (max-width:760px){
  .row{grid-template-columns:26px minmax(0,1fr);row-gap:12px;padding:16px 0}
  .fix{grid-column:2;padding-left:0}
  .more{grid-template-rows:1fr}.more > span{padding-top:8px}
  .links a::after{display:none}
}
@media (prefers-reduced-motion:reduce){
  *,*::before,*::after{animation:none!important;transition-duration:.01ms!important}
  .row:not(.next){--scroll:1}
  h1 mark::before{transform:skew(-5deg) scaleX(1)}
  h1 mark{color:#0a0c10}
}
`;

const themeColors = `<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#0a0b0d"><meta name="theme-color" media="(prefers-color-scheme: light)" content="#fafbfc">`;
const iconLinks = `<link rel="icon" href="/favicon.ico" sizes="48x48"><link rel="icon" type="image/svg+xml" href="/favicon.svg"><link rel="icon" type="image/png" sizes="192x192" href="/icon-192.png"><link rel="apple-touch-icon" href="/apple-touch-icon.png"><link rel="manifest" href="/manifest.webmanifest">`;
const baseHead = (title) =>
  `<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title><meta name="color-scheme" content="light dark">${themeColors}${iconLinks}<link rel="preload" href="/fonts/geist-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin><style>${css}</style>`;

// The schema.org type follows the kind. An unknown kind fails the build rather than being described as something else.
const appLd = (a) => {
  const base = { "@id": appId(a), name: a.name, description: a.description, url: appUrl(a), author: { "@id": personId }, ...(a.repo ? { sameAs: [a.repo] } : {}) };
  const free = { isAccessibleForFree: true, offers: { "@type": "Offer", price: "0", priceCurrency: "USD" } };
  switch (a.kind) {
    case "macos":
      return { "@type": "SoftwareApplication", ...base, applicationCategory: "UtilitiesApplication", operatingSystem: "macOS", ...free };
    case "editor":
      return { "@type": "SoftwareApplication", ...base, applicationCategory: "DeveloperApplication", operatingSystem: "Windows, macOS, Linux", ...free };
    case "webapp":
      return { "@type": "WebApplication", ...base, applicationCategory: a.category ?? "UtilitiesApplication", operatingSystem: "Any (web browser)", ...free };
    case "website":
      return { "@type": "WebSite", ...base, inLanguage: "en", publisher: { "@id": personId } };
    default:
      throw new Error(`apps.json: unknown kind "${a.kind}" for "${a.slug}"`);
  }
};
const graph = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": `${url}#site`,
      name: siteName,
      url,
      description: site.description,
      inLanguage: "en",
      publisher: { "@id": personId },
    },
    {
      "@type": "Person",
      "@id": personId,
      name: owner.name,
      url: owner.url,
      image: `${origin}/pfp.jpg`,
      description: owner.tagline,
      knowsAbout: owner.tagline.split("·").map((s) => s.trim()),
      sameAs: owner.links.map((l) => l.url),
    },
    {
      "@type": "CollectionPage",
      "@id": `${url}#page`,
      url,
      name: site.title,
      description: site.description,
      inLanguage: "en",
      isPartOf: { "@id": `${url}#site` },
      about: { "@id": personId },
      primaryImageOfPage: { "@type": "ImageObject", url: ogImage, width: 1200, height: 630 },
      mainEntity: {
        "@type": "ItemList",
        itemListElement: apps.map((a, i) => ({ "@type": "ListItem", position: i + 1, url: appUrl(a), item: { "@id": appId(a) } })),
      },
    },
    ...apps.map(appLd),
  ],
};

const indexHead = `${baseHead(site.title)}<meta name="description" content="${esc(site.description)}"><link rel="canonical" href="${url}"><meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1"><meta name="author" content="${esc(owner.name)}"><link rel="author" href="${esc(owner.url)}">${owner.links.map((l) => `<link rel="me" href="${esc(l.url)}">`).join("")}<link rel="alternate" type="text/markdown" href="/index.md" title="Markdown"><link rel="sitemap" type="application/xml" href="/sitemap.xml"><meta property="og:type" content="website"><meta property="og:site_name" content="${esc(siteName)}"><meta property="og:title" content="${esc(site.title)}"><meta property="og:description" content="${esc(site.description)}"><meta property="og:url" content="${url}"><meta property="og:locale" content="en"><meta property="og:image" content="${ogImage}"><meta property="og:image:type" content="image/png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="${esc(`${siteName}: ${head1} ${head2}`)}"><meta name="twitter:card" content="summary_large_image">${xHandle ? `<meta name="twitter:site" content="${xHandle}"><meta name="twitter:creator" content="${xHandle}">` : ""}<meta name="twitter:title" content="${esc(site.title)}"><meta name="twitter:description" content="${esc(site.description)}"><meta name="twitter:image" content="${ogImage}"><meta name="twitter:image:alt" content="${esc(`${siteName}: ${head1} ${head2}`)}"><script type="application/ld+json">${JSON.stringify(graph).replace(/</g, "\\u003c")}</script>`;

const doc = (head, body) => `<!doctype html><html lang="en"><head>${head}</head><body>${body}</body></html>`;
const topHtml = `<header class="top"><a class="who" href="${esc(owner.url)}"><img src="${pfp}" alt="" width="34" height="34"><span>${esc(owner.name)}</span></a><nav class="links" aria-label="${esc(owner.name)} elsewhere">${links}</nav></header>`;

write(
  "index.html",
  doc(
    indexHead,
    `<main>${topHtml}<section class="hero"><h1><span class="l">${esc(head1)}</span> <span class="l" data-sticker="${apps.length} so far"><mark>${esc(head2)}</mark></span></h1></section>${filters}<div class="groups">${groupsHtml}${nextHtml}</div></main>`,
  ),
);
write(
  "404.html",
  doc(
    `${baseHead(`Not found · ${siteName}`)}<meta name="robots" content="noindex">`,
    `<main>${topHtml}<section class="hero"><h1><span class="l">This page</span> <span class="l"><mark>wandered off.</mark></span></h1></section><div class="groups"><section class="group"><div class="gin"><span class="gl"></span><div class="rows"><a class="row" href="/" style="--i:0">${tick}<span class="said"><span class="line">I fixed a lot of things. Not this one.</span></span><span class="fix"><b>Back to the apps</b>${arrow}</span></a></div></div></section></div></main>`,
  ),
);
console.log(`hub: ${apps.length} app(s) -> ${out}`);
