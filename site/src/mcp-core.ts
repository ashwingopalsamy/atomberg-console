// The read-only tool set, shared by the browser (WebMCP) and the Worker (remote MCP).
// Pure functions over the knowledge file, so both surfaces return the same text as the pages.

export interface Knowledge {
  pages: { slug: string; url: string; title: string; description: string; markdown: string }[];
  faq: { id: string; q: string; a: string; app: boolean }[];
  release: { version: string; date: string; notes: string; url: string } | null;
  install: Record<string, string[]>;
  privacy: Record<string, unknown>;
  budget: Record<string, unknown>;
}

export interface ToolDef {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
  annotations: { readOnlyHint: true; openWorldHint: false; idempotentHint: true };
}

const annotations = { readOnlyHint: true, openWorldHint: false, idempotentHint: true } as const;

export const TOOLS: ToolDef[] = [
  {
    name: "search_docs",
    title: "Search the docs",
    description:
      "Search Atomberg Console's documentation (install, privacy, call budget, local control, FAQ, changelog). Returns matching pages with a snippet and URL.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "What to look for, in plain words." },
        limit: { type: "integer", minimum: 1, maximum: 10, default: 5 },
      },
      required: ["query"],
      additionalProperties: false,
    },
    annotations,
  },
  {
    name: "get_faq",
    title: "Get FAQ answers",
    description: "Return frequently asked questions and answers. Optionally filter by a topic word.",
    inputSchema: {
      type: "object",
      properties: { topic: { type: "string", description: "Optional word to filter on, e.g. 'keychain' or 'local'." } },
      additionalProperties: false,
    },
    annotations,
  },
  {
    name: "get_install_steps",
    title: "Get install steps",
    description: "Return the steps to install Atomberg Console with Homebrew, a DMG, or from source.",
    inputSchema: {
      type: "object",
      properties: { method: { type: "string", enum: ["homebrew", "dmg", "source"] } },
      additionalProperties: false,
    },
    annotations,
  },
  {
    name: "get_privacy_policy",
    title: "Get the privacy facts",
    description:
      "Return exactly which hosts and ports the app contacts, what it stores and where, and that it has no analytics, telemetry, updater or dependencies.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations,
  },
  {
    name: "get_call_budget",
    title: "Get the call budget",
    description:
      "Return what each action costs against Atomberg's 100 cloud calls a day: refresh, local command, cloud command, token.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations,
  },
  {
    name: "get_release",
    title: "Get the latest release",
    description: "Return the latest version, its date, its notes and the release URL.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations,
  },
];

function snippet(text: string, terms: string[]): string {
  const flat = text.replace(/[#*`|>\-]+/g, " ").replace(/\s+/g, " ");
  const lower = flat.toLowerCase();
  const hit = terms.map((t) => lower.indexOf(t)).filter((i) => i >= 0).sort((a, b) => a - b)[0] ?? 0;
  const start = Math.max(0, hit - 60);
  return (start > 0 ? "…" : "") + flat.slice(start, start + 220).trim() + (start + 220 < flat.length ? "…" : "");
}

export function run(name: string, input: Record<string, unknown>, k: Knowledge, origin = "https://apps.ashwingopalsamy.in"): unknown {
  switch (name) {
    case "search_docs": {
      const query = String(input.query ?? "").toLowerCase().trim();
      const limit = Math.min(10, Math.max(1, Number(input.limit ?? 5)));
      const terms = query.split(/[^a-z0-9.]+/).filter((t) => t.length > 1);
      if (terms.length === 0) return { results: [] };
      const scored = k.pages
        .map((p) => {
          const hay = { title: p.title.toLowerCase(), desc: p.description.toLowerCase(), body: p.markdown.toLowerCase() };
          const score = terms.reduce(
            (s, t) => s + 5 * count(hay.title, t) + 3 * count(hay.desc, t) + count(hay.body, t),
            0,
          );
          return { p, score };
        })
        .filter((r) => r.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, limit);
      return {
        results: scored.map(({ p }) => ({
          title: p.title,
          url: `${origin}${p.url}`,
          markdown: `${origin}${p.url.replace(/\/$/, "")}.md`,
          snippet: snippet(p.markdown, terms),
        })),
      };
    }
    case "get_faq": {
      const topic = String(input.topic ?? "").toLowerCase().trim();
      const items = k.faq.filter((f) => !topic || `${f.q} ${f.a}`.toLowerCase().includes(topic));
      return { faq: items.map(({ q, a }) => ({ question: q, answer: a })), url: `${origin}/atomberg-console/faq/` };
    }
    case "get_install_steps": {
      const method = String(input.method ?? "");
      return method && k.install[method] ? { [method]: k.install[method] } : k.install;
    }
    case "get_privacy_policy":
      return { ...k.privacy, url: `${origin}/atomberg-console/privacy/` };
    case "get_call_budget":
      return { ...k.budget, url: `${origin}/atomberg-console/call-budget/` };
    case "get_release":
      return k.release ?? { error: "no release yet" };
    default:
      throw new Error(`unknown tool: ${name}`);
  }
}

function count(haystack: string, needle: string): number {
  let n = 0;
  for (let i = haystack.indexOf(needle); i >= 0; i = haystack.indexOf(needle, i + needle.length)) n++;
  return n;
}
