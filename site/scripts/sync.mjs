// Turns the repository's docs into site pages and one knowledge file. Runs before dev and build.
// docs/*.md and CHANGELOG.md stay the source of truth; nothing here is edited by hand.
import { readFileSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const repo = join(root, "..");
const base = "/atomberg-console";
const gh = "https://github.com/ashwingopalsamy/atomberg-console";

const pages = [
  { slug: "install", src: "site/content/install.md", title: "Install", description: "Install with Homebrew, a DMG or from source, then paste your API key and refresh token once.", order: 1 },
  { slug: "call-budget", src: "docs/BUDGET.md", title: "The 100-call budget", description: "A refresh costs one call, a command to a fan on your Wi-Fi costs none, a cloud command costs one, against 100 calls a day.", order: 3 },
  { slug: "local-control", src: "docs/TROUBLESHOOTING.md", title: "Why isn't my fan found locally?", description: "The fan and your Mac are not on the same Wi-Fi, or macOS is blocking Local Network access for the app.", order: 4 },
  { slug: "privacy", src: "docs/PRIVACY.md", title: "Privacy", description: "Two destinations, no analytics, credentials only in your Keychain, and three commands to check it yourself.", order: 5 },
  { slug: "developers", src: "docs/MCP.md", title: "Developers and agents", description: "Read-only WebMCP and remote MCP tools for the docs, llms.txt, and the planned local MCP contract for the app.", order: 6 },
  { slug: "design", src: "docs/DESIGN.md", title: "Design", description: "Principles, tokens, layout and status glyphs of the app.", order: 7 },
  { slug: "changelog", src: "CHANGELOG.md", title: "Changelog", description: "What changed in each release.", order: 8 },
];

// Where a docs link lands on the single page. Pages without a section link to the repository instead.
const anchors = { install: "#install", "call-budget": "#budget", "local-control": "#local", privacy: "#privacy" };
const slugBySource = {
  "docs/PRIVACY.md": "privacy", "PRIVACY.md": "privacy",
  "docs/BUDGET.md": "call-budget", "BUDGET.md": "call-budget",
  "docs/TROUBLESHOOTING.md": "local-control", "TROUBLESHOOTING.md": "local-control",
};

function rewriteLinks(md) {
  return md.replace(/\]\((?!https?:|#|\/|mailto:)([^)]+)\)/g, (_, target) => {
    const [path, hash] = target.split("#");
    const name = path.replace(/^(\.\.\/|\.\/)+/, "");
    const slug = slugBySource[name] ?? slugBySource[name.replace(/^docs\//, "")];
    if (slug && anchors[slug]) return `](${base}/${anchors[slug]})`;
    return `](${gh}/blob/main/${name}${hash ? "#" + hash : ""})`;
  });
}

// Shell blocks are highlighted here, at build time, so the page needs no script and no highlighter dependency.
const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const span = (cls, t) => `<span class="${cls}">${esc(t)}</span>`;
function highlightLine(line) {
  if (/^\s*#/.test(line)) return span("o", line);
  const token = /("(?:[^"\\]|\\.)*"|'[^']*')|(&&|\|\||\||;|\\$)|(\s+)|([^\s"'|&;]+)/g;
  let out = "";
  let command = true;
  for (const m of line.matchAll(token)) {
    if (m[1]) {
      out += m[1].startsWith("'")
        ? span("s", m[1])
        : m[1].split(/(\$\([^)]*\)|\$\{[^}]*\}|\$[A-Za-z_]+)/).map((part, i) => (i % 2 ? span("v", part) : part ? span("s", part) : "")).join("");
      command = false;
    } else if (m[2]) {
      out += span("o", m[2]);
      if (m[2] !== "\\") command = true;
    } else if (m[3]) {
      out += m[3];
    } else {
      const w = m[4];
      out += span(command ? "c" : w.startsWith("-") ? "f" : /^\d+$/.test(w) ? "v" : /[\/.*]/.test(w) ? "u" : "a", w);
      command = false;
    }
  }
  return out;
}
const highlightFences = (md) =>
  md.replace(/```(?:sh|bash|shell)\n([\s\S]*?)```/g, (_, code) =>
    `<pre class="code"><code>${code.replace(/\n$/, "").split("\n").map(highlightLine).join("\n")}</code></pre>`);

const frontmatter = (o) =>
  "---\n" + Object.entries(o).map(([k, v]) => `${k}: ${JSON.stringify(v)}`).join("\n") + "\n---\n";

const knowledge = { pages: [], faq: [], release: null };
mkdirSync(join(root, "src/generated"), { recursive: true });
// Earlier builds rendered each doc as its own route; the site is one page now.
rmSync(join(root, "src/pages/_docs"), { recursive: true, force: true });
mkdirSync(join(root, "src/content-md"), { recursive: true });

for (const page of pages) {
  const raw = readFileSync(join(repo, page.src), "utf8");
  // The page renders the title and the answer line itself.
  const body = rewriteLinks(raw.replace(/^# .*\n+/, "").replace(/^\*\*Short answer:\*\*.*\n+/, "").replace(/^Short answer: .*\n+/, ""));
  writeFileSync(join(root, "src/content-md", `${page.slug}.md`), highlightFences(body));
  knowledge.pages.push({
    slug: page.slug,
    url: `${base}/`,
    anchor: anchors[page.slug] ?? null,
    title: page.title,
    description: page.description,
    markdown: `# ${page.title}\n\n${page.description}\n\n${body.trim()}\n`,
    source: `${gh}/blob/main/${page.src}`,
  });
}

knowledge.faq = JSON.parse(readFileSync(join(repo, "docs/faq.json"), "utf8"));

// Latest release from the changelog.
const log = readFileSync(join(repo, "CHANGELOG.md"), "utf8");
const m = log.match(/^## \[([^\]]+)\] - (\d{4}-\d{2}-\d{2})\n([\s\S]*?)(?=^## \[|\s*$(?![\s\S]))/m);
if (m) {
  knowledge.release = { version: m[1], date: m[2], notes: m[3].trim(), url: `${gh}/releases/tag/v${m[1]}` };
}

knowledge.install = {
  homebrew: ["brew install --cask ashwingopalsamy/tap/atomberg-console"],
  dmg: [
    `Download Atomberg-Console-${knowledge.release?.version ?? "1.0.0"}.dmg from ${gh}/releases/latest`,
    "shasum -a 256 -c Atomberg-Console-*.dmg.sha256",
    "gh attestation verify Atomberg-Console-*.dmg -R ashwingopalsamy/atomberg-console",
    "Drag Atomberg Console.app to Applications. Right-click, Open, the first time (it is not notarised).",
  ],
  source: [
    `git clone ${gh} && cd atomberg-console`,
    'scripts/bundle.sh && open "build/Atomberg Console.app"',
  ],
};
knowledge.privacy = {
  cloudHost: "api.developer.atomberg-iot.com",
  cloudScheme: "https",
  udpPorts: [5625, 5600],
  analytics: false,
  telemetry: false,
  updater: false,
  dependencies: 0,
  stores: {
    credentials: "macOS Keychain, item com.ashwin.ATOMBERG",
    catalogue: "~/Library/Application Support/ATOMBERG/catalogue.json",
    quota: "~/Library/Application Support/ATOMBERG/quota.json",
    callLog: "~/Library/Application Support/ATOMBERG/calls.log (method, path, status; no secrets)",
  },
};
knowledge.budget = {
  dailyLimit: 100,
  perSecond: 5,
  resetsAt: "00:00 UTC",
  costs: [
    { action: "refresh all devices", calls: 1 },
    { action: "command to a fan heard on your Wi-Fi", calls: 0 },
    { action: "command to a fan through the cloud", calls: 1 },
    { action: "command to a purifier", calls: 1 },
    { action: "usage figures (kWh, hours)", calls: "at most 1 a day" },
    { action: "access token", calls: "about 1 a day" },
  ],
};

writeFileSync(join(root, "src/generated/knowledge.json"), JSON.stringify(knowledge, null, 2));
console.log(`sync: ${pages.length} pages, ${knowledge.faq.length} faq entries`);
