// Writes the hub's root files from apps.json, so adding an app is one JSON entry and one service binding.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "public");
const { host, owner, apps } = JSON.parse(readFileSync(join(here, "apps.json"), "utf8"));
const origin = `https://${host}`;
const write = (name, text) => {
  mkdirSync(dirname(join(out, name)), { recursive: true });
  writeFileSync(join(out, name), text);
};
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");

const bots = ["GPTBot", "OAI-SearchBot", "ChatGPT-User", "ClaudeBot", "Claude-User", "Claude-SearchBot", "PerplexityBot", "Perplexity-User", "Google-Extended", "Applebot-Extended", "CCBot"];
write(
  "robots.txt",
  `User-agent: *\nAllow: /\n\n${bots.map((b) => `User-agent: ${b}\nAllow: /\n`).join("\n")}\nSitemap: ${origin}/sitemap.xml\n`,
);
write(
  "sitemap.xml",
  `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${apps
    .map((a) => `  <sitemap><loc>${origin}/${a.slug}/sitemap.xml</loc></sitemap>`)
    .join("\n")}\n</sitemapindex>\n`,
);
write(
  "llms.txt",
  `# Apps by ${owner.name}\n\n> Small, source-available apps. Each has its own llms.txt.\n\n## Apps\n${apps
    .map((a) => `- [${a.name}](${origin}/${a.slug}/llms.txt): ${a.description}`)
    .join("\n")}\n`,
);
write(
  ".well-known/mcp.json",
  JSON.stringify({ servers: apps.map((a) => ({ name: a.name, card: `${origin}/${a.slug}/.well-known/mcp.json` })) }, null, 2) + "\n",
);
write(
  ".well-known/security.txt",
  `Contact: ${apps[0].repo}/security/advisories/new\nExpires: 2027-10-11T00:00:00.000Z\nPreferred-Languages: en\nCanonical: ${origin}/.well-known/security.txt\n`,
);
write("humans.txt", `Apps by ${owner.name}, ${owner.url}\n`);

const items = apps
  .map(
    (a) => `<a class="app" href="/${a.slug}/"><img src="/${a.slug}/icon-192.png" alt="" width="52" height="52"><span><b>${esc(a.name)}</b><small>${esc(a.description)}</small></span></a>`,
  )
  .join("");
const page = (title, body) => `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><meta name="color-scheme" content="dark"><meta name="theme-color" content="#0e0f10"><link rel="canonical" href="${origin}/"><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;min-height:100dvh;display:grid;place-items:center;padding:24px;background:radial-gradient(900px 420px at 50% -10%,oklch(.26 .006 240/.55),transparent 70%),oklch(.145 .003 240);color:oklch(.985 0 0);font:400 1rem/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}
main{width:min(100%,460px)}h1{font-size:.8rem;font-weight:500;letter-spacing:.04em;text-transform:uppercase;color:oklch(.62 .006 240);margin:0 0 14px}
.app{display:flex;gap:16px;align-items:center;padding:14px;border-radius:20px;border:1px solid oklch(.255 .004 240);background:oklch(.18 .003 240);color:inherit;text-decoration:none;transition:background .2s,border-color .2s,transform .3s cubic-bezier(.16,1,.3,1)}
.app:hover{background:oklch(.215 .004 240);border-color:oklch(.32 .005 240);transform:translateY(-2px)}.app:active{transform:scale(.985)}
.app img{border-radius:14px}.app b{display:block;font-weight:600;letter-spacing:-.01em}.app small{color:oklch(.62 .006 240);font-size:.88rem}
p{margin:18px 4px 0;color:oklch(.46 .006 240);font-size:.8rem}a:focus-visible{outline:2px solid #fff;outline-offset:3px}
</style></head><body><main>${body}</main></body></html>`;
write("index.html", page("Apps by Ashwin Gopalsamy", `<h1>Apps</h1>${items}<p>By <a href="${owner.url}" style="color:inherit">${esc(owner.name)}</a>. Source-available, no analytics.</p>`));
write("404.html", page("Not found", `<h1>Not found</h1><a class="app" href="/"><span><b>Back to the apps</b><small>${origin}</small></span></a>`));
console.log(`hub: ${apps.length} app(s) -> ${out}`);
