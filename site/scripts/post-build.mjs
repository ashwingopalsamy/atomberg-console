// The machine layer: Markdown mirrors, sitemap, llms files, feed and the knowledge file, written into dist/.
// Everything is derived from src/generated/knowledge.json and CHANGELOG.md, so a page and its mirror cannot disagree.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");
const knowledge = JSON.parse(readFileSync(join(root, "src/generated/knowledge.json"), "utf8"));
const changelog = readFileSync(join(root, "..", "CHANGELOG.md"), "utf8");

const ORIGIN = "https://apps.ashwingopalsamy.in";
const BASE = "/atomberg-console/";
const REPO = "https://github.com/ashwingopalsamy/atomberg-console";
const abs = (path = "") => `${ORIGIN}${BASE}${path}`;
const summary =
  "An unofficial macOS menu bar app for Atomberg fans, water purifiers and locks. It controls fans over your Wi-Fi (UDP 5625 and 5600) and falls back to Atomberg's cloud API, spending at most one of the 100 daily calls per command. One cloud host, no dependencies, no analytics. Source-available under PolyForm Noncommercial 1.0.0. Not affiliated with Atomberg.";
const release = knowledge.release;
const lastmod = release?.date ?? new Date().toISOString().slice(0, 10);

const write = (name, text) => {
  const file = join(dist, name);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, text);
};
const absolutise = (md) => md.replaceAll(`](${BASE}`, `](${ORIGIN}${BASE}`);
const xml = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// Markdown mirrors: /<slug>.md next to /<slug>/
const mirrors = knowledge.pages.map((p) => ({
  ...p,
  text: `# ${p.title}\n\n> ${p.description}\n\nCanonical: ${abs(p.anchor ?? "")}\n\n${absolutise(p.markdown).trim()}\n`,
}));
for (const m of mirrors) write(`${m.slug}.md`, m.text);

const faqText = (knowledge.faq ?? []).map((f) => `## ${f.q}\n\n${f.a}\n`).join("\n");
write("faq.md", `# FAQ\n\n> Short answers about Atomberg Console.\n\nCanonical: ${abs("faq/")}\n\n${faqText}`);

const sections = [
  ["Start here", ["install", "call-budget", "local-control", "privacy"]],
  ["Reference", ["developers", "design", "changelog", "unofficial"]],
];
const bySlug = Object.fromEntries(mirrors.map((m) => [m.slug, m]));
const homeLinks = sections
  .map(([name, slugs]) => `## ${name}\n${slugs.map((s) => `- [${bySlug[s].title}](${abs(`${s}.md`)}): ${bySlug[s].description}`).join("\n")}`)
  .join("\n\n");
const llms = `# Atomberg Console\n\n> ${summary}\n\n${homeLinks}\n\n## Optional\n- [FAQ](${abs("faq.md")}): short answers, also as JSON-LD on the page.\n- [Source](${REPO}): Swift 6, no dependencies.\n- [Releases](${REPO}/releases): DMG, checksum and build attestation.\n- [MCP server](${abs("mcp")}): read-only tools over the docs, streamable HTTP.\n`;
write("index.md", `# Atomberg Console\n\n> ${summary}\n\nCanonical: ${abs()}\n\n${homeLinks}\n`);
write("llms.txt", llms);
write(
  "llms-full.txt",
  `# Atomberg Console\n\n> ${summary}\n\n${mirrors.map((m) => m.text).join("\n---\n\n")}\n---\n\n# FAQ\n\n${faqText}`,
);

// sitemap
const urls = [""];
write(
  "sitemap.xml",
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls
    .map((u) => `  <url><loc>${abs(u)}</loc><lastmod>${lastmod}</lastmod></url>`)
    .join("\n")}\n</urlset>\n`,
);

// Atom feed from CHANGELOG.md
const entries = [...changelog.matchAll(/^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})\n([\s\S]*?)(?=^## \[|\s*$(?![\r\n]))/gm)].map(
  (m) => ({ version: m[1], date: m[2], notes: m[3].trim() }),
);
write(
  "feed.xml",
  `<?xml version="1.0" encoding="UTF-8"?>\n<feed xmlns="http://www.w3.org/2005/Atom">\n  <title>Atomberg Console releases</title>\n  <id>${abs("feed.xml")}</id>\n  <link rel="self" href="${abs("feed.xml")}"/>\n  <link href="${abs("changelog/")}"/>\n  <updated>${lastmod}T00:00:00Z</updated>\n  <author><name>Ashwin Gopalsamy</name></author>\n${entries
    .map(
      (e) =>
        `  <entry>\n    <title>${xml(e.version)}</title>\n    <id>${REPO}/releases/tag/v${e.version}</id>\n    <link href="${REPO}/releases/tag/v${e.version}"/>\n    <updated>${e.date}T00:00:00Z</updated>\n    <content type="text">${xml(e.notes)}</content>\n  </entry>`,
    )
    .join("\n")}\n</feed>\n`,
);

write("knowledge.json", JSON.stringify(knowledge));
console.log(`post-build: ${mirrors.length + 2} markdown mirrors, ${urls.length} sitemap urls, ${entries.length} feed entries`);
