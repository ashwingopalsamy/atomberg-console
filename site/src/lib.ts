import knowledge from "./generated/knowledge.json";

export const ORIGIN = "https://apps.ashwingopalsamy.in";
export const BASE = "/atomberg-console/";
export const REPO = "https://github.com/ashwingopalsamy/atomberg-console";
export const LICENSE = "https://polyformproject.org/licenses/noncommercial/1.0.0/";
export const NAME = "Atomberg Console";
export const TAGLINE = "a menu bar app for atomberg fans, purifiers and locks";

export const faq = knowledge.faq as { id: string; q: string; a: string; app: boolean }[];
export const pages = knowledge.pages as { slug: string; url: string; title: string; description: string }[];
export const release = knowledge.release as { version: string; date: string; notes: string; url: string } | null;

export const absolute = (path = "") => `${ORIGIN}${BASE}${path}`;

const author = {
  "@type": "Person",
  "@id": "https://ashwingopalsamy.in/#person",
  name: "Ashwin Gopalsamy",
  url: "https://ashwingopalsamy.in",
};

export function softwareApplication() {
  return {
    "@type": "SoftwareApplication",
    "@id": `${absolute()}#app`,
    name: NAME,
    description:
      "A macOS menu bar app for Atomberg fans, water purifiers and locks. Controls fans over your Wi-Fi (UDP) and falls back to Atomberg's cloud API, spending at most one of the 100 daily calls per command.",
    url: absolute(),
    applicationCategory: "UtilitiesApplication",
    operatingSystem: "macOS 26 or later",
    softwareVersion: release?.version ?? "1.0.0",
    datePublished: release?.date ?? "2026-10-11",
    license: LICENSE,
    isAccessibleForFree: true,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    downloadUrl: `${REPO}/releases/latest`,
    installUrl: absolute("#install"),
    softwareRequirements: "macOS 26 or later; an Atomberg account with Developer Mode on",
    keywords: ["Atomberg", "menu bar app", "macOS", "smart fan", "air purifier", "smart lock", "local control", "UDP"],
    publisher: author,
    featureList: [
      "Local control of fans over UDP 5625 and 5600",
      "Cloud fallback within Atomberg's 100 calls a day",
      "Menu bar count of running fans",
      "Per-row speed control",
      "One network host, no dependencies, no analytics",
    ],
    author,
    sameAs: [REPO],
  };
}

export function webSite() {
  return {
    "@type": "WebSite",
    "@id": `${absolute()}#site`,
    name: NAME,
    url: absolute(),
    inLanguage: "en",
    publisher: author,
  };
}

export function sourceCode() {
  return {
    "@type": "SoftwareSourceCode",
    name: `${NAME} source`,
    codeRepository: REPO,
    programmingLanguage: "Swift",
    runtimePlatform: "macOS",
    license: LICENSE,
    author,
  };
}

export function breadcrumbs(items: { name: string; path: string }[]) {
  return {
    "@type": "BreadcrumbList",
    itemListElement: [{ name: NAME, path: "" }, ...items].map((item, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: item.name,
      item: absolute(item.path),
    })),
  };
}

export function faqPage(entries = faq) {
  return {
    "@type": "FAQPage",
    mainEntity: entries.map((e) => ({
      "@type": "Question",
      name: e.q,
      acceptedAnswer: { "@type": "Answer", text: e.a },
    })),
  };
}

export function howToInstall() {
  const steps = [
    "Install with Homebrew: brew install --cask ashwingopalsamy/tap/atomberg-console, or download the DMG from the latest release.",
    "In the Atomberg Home app, turn on Developer Mode and copy the API key and refresh token.",
    "Open Atomberg Console and paste both values. They are stored in your Keychain.",
    "Allow Local Network access when macOS asks, so fans are controlled directly over your Wi-Fi.",
  ];
  return {
    "@type": "HowTo",
    name: "Install and set up Atomberg Console",
    totalTime: "PT3M",
    tool: [{ "@type": "HowToTool", name: "Atomberg Home app (Developer Mode)" }],
    step: steps.map((text, i) => ({ "@type": "HowToStep", position: i + 1, text })),
  };
}

export const graph = (...nodes: object[]) => ({ "@context": "https://schema.org", "@graph": nodes });
