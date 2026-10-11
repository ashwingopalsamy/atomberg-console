// Turns the repository's docs into site pages and one knowledge file. Runs before dev and build.
// docs/*.md and CHANGELOG.md stay the source of truth; nothing here is edited by hand.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const repo = join(root, "..");
const base = "/atomberg-console";
const gh = "https://github.com/ashwingopalsamy/atomberg-console";

const pages = [
  { slug: "install", src: "site/content/install.md", title: "Install", description: "Install with Homebrew, a DMG or from source, then paste your API key and refresh token once.", order: 1 },
  { slug: "calls-no-one", src: "site/content/calls-no-one.md", title: "Calls no one", description: "It contacts one cloud host and two UDP ports on your own network. Nothing else, enforced in code and checked in CI.", order: 2 },
  { slug: "call-budget", src: "docs/BUDGET.md", title: "The 100-call budget", description: "A refresh costs one call, a command to a fan on your Wi-Fi costs none, a cloud command costs one, against 100 calls a day.", order: 3 },
  { slug: "local-control", src: "docs/TROUBLESHOOTING.md", title: "Why isn't my fan found locally?", description: "The fan and your Mac are not on the same Wi-Fi, or macOS is blocking Local Network access for the app.", order: 4 },
  { slug: "privacy", src: "docs/PRIVACY.md", title: "Privacy", description: "Two destinations, no analytics, credentials only in your Keychain, and three commands to check it yourself.", order: 5 },
  { slug: "developers", src: "docs/MCP.md", title: "Developers and agents", description: "Read-only WebMCP and remote MCP tools for the docs, llms.txt, and the planned local MCP contract for the app.", order: 6 },
  { slug: "design", src: "docs/DESIGN.md", title: "Design", description: "Principles, tokens, layout and status glyphs of the app.", order: 7 },
  { slug: "changelog", src: "CHANGELOG.md", title: "Changelog", description: "What changed in each release.", order: 8 },
  { slug: "unofficial", src: "site/content/unofficial.md", title: "Unofficial", description: "Independent project, not affiliated with Atomberg, free for noncommercial use.", order: 9 },
];

const slugBySource = {
  "docs/PRIVACY.md": "privacy", "PRIVACY.md": "privacy",
  "docs/BUDGET.md": "call-budget", "BUDGET.md": "call-budget",
  "docs/TROUBLESHOOTING.md": "local-control", "TROUBLESHOOTING.md": "local-control",
  "docs/MCP.md": "developers", "MCP.md": "developers",
  "docs/DESIGN.md": "design", "DESIGN.md": "design",
  "CHANGELOG.md": "changelog", "NOTICE.md": null,
};

function rewriteLinks(md) {
  return md.replace(/\]\((?!https?:|#|\/|mailto:)([^)]+)\)/g, (_, target) => {
    const [path, hash] = target.split("#");
    const name = path.replace(/^(\.\.\/|\.\/)+/, "");
    const slug = slugBySource[name] ?? slugBySource[name.replace(/^docs\//, "")];
    if (slug) return `](${base}/${slug}/${hash ? "#" + hash : ""})`;
    return `](${gh}/blob/main/${name.startsWith("docs/") || /\.(md|sh|swift|json|yml)$/.test(name) ? name : name}${hash ? "#" + hash : ""})`;
  });
}

const frontmatter = (o) =>
  "---\n" + Object.entries(o).map(([k, v]) => `${k}: ${JSON.stringify(v)}`).join("\n") + "\n---\n";

const knowledge = { pages: [], faq: [], release: null };
mkdirSync(join(root, "src/generated"), { recursive: true });
mkdirSync(join(root, "src/pages"), { recursive: true });

for (const page of pages) {
  const raw = readFileSync(join(repo, page.src), "utf8");
  // The layout renders the title and the answer line itself.
  const body = rewriteLinks(raw.replace(/^# .*\n+/, "").replace(/^\*\*Short answer:\*\*.*\n+/, ""));
  const sourcePath = page.src.startsWith("site/") ? `${gh}/blob/main/${page.src}` : `${gh}/blob/main/${page.src}`;
  writeFileSync(
    join(root, "src/pages", `${page.slug}.md`),
    frontmatter({
      layout: "../layouts/Doc.astro",
      title: page.title,
      description: page.description,
      slug: page.slug,
      source: sourcePath,
      order: page.order,
    }) + "\n" + body,
  );
  knowledge.pages.push({
    slug: page.slug,
    url: `${base}/${page.slug}/`,
    title: page.title,
    description: page.description,
    markdown: `# ${page.title}\n\n${page.description}\n\n${body.trim()}\n`,
    source: sourcePath,
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
