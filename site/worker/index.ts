// The app Worker: static assets, a read-only MCP endpoint, Markdown for agents, and security headers.
// The hub forwards /atomberg-console/* here untouched; the prefix is removed below so one build serves both.
import { TOOLS, run, type Knowledge } from "../src/mcp-core";
import knowledge from "../src/generated/knowledge.json";

interface Env {
  ASSETS: { fetch(request: Request): Promise<Response> };
}

const ORIGIN = "https://apps.ashwingopalsamy.in";
const PREFIX = "/atomberg-console";
const SERVER = { name: "atomberg-console-docs", title: "Atomberg Console docs", version: "1.0.0" };
const PROTOCOLS = ["2025-06-18", "2025-03-26", "2024-11-05"];
const MAX_BODY = 16 * 1024;
const MAX_BATCH = 16;
const INSTRUCTIONS =
  "Read-only documentation tools for Atomberg Console, an unofficial macOS menu bar app for Atomberg fans. No credentials are needed or accepted.";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type, accept, mcp-protocol-version, mcp-session-id",
  "access-control-max-age": "86400",
};

const CSP = [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self'",
  "connect-src 'self'",
  "manifest-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

const REPO = "https://github.com/ashwingopalsamy/atomberg-console";
const MOVED: Record<string, string> = {
  "/install": "#install",
  "/call-budget": "#budget",
  "/local-control": "#local",
  "/privacy": "#privacy",
  "/calls-no-one": "#privacy",
  "/faq": "#faq",
  "/unofficial": "",
  "/developers": `${REPO}/blob/main/docs/MCP.md`,
  "/design": `${REPO}/blob/main/docs/DESIGN.md`,
  "/changelog": `${REPO}/blob/main/CHANGELOG.md`,
};

type Rpc = { jsonrpc?: string; id?: string | number | null; method?: string; params?: Record<string, unknown> };

const reply = (id: Rpc["id"], result: unknown) => ({ jsonrpc: "2.0", id: id ?? null, result });
const fail = (id: Rpc["id"], code: number, message: string) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });

function handle(message: Rpc) {
  if (!message || message.jsonrpc !== "2.0" || typeof message.method !== "string") return fail(message?.id, -32600, "Invalid request");
  // Notifications carry no id and get no response.
  if (message.id === undefined) return null;
  const params = message.params ?? {};
  switch (message.method) {
    case "initialize": {
      const asked = String(params.protocolVersion ?? "");
      return reply(message.id, {
        protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER,
        instructions: INSTRUCTIONS,
      });
    }
    case "ping":
      return reply(message.id, {});
    case "tools/list":
      return reply(message.id, { tools: TOOLS });
    case "tools/call": {
      const name = String(params.name ?? "");
      if (!TOOLS.some((t) => t.name === name)) return fail(message.id, -32602, `Unknown tool: ${name}`);
      try {
        const args = (params.arguments ?? {}) as Record<string, unknown>;
        const out = run(name, args, knowledge as unknown as Knowledge, ORIGIN);
        return reply(message.id, {
          content: [{ type: "text", text: JSON.stringify(out, null, 2) }],
          structuredContent: out,
          isError: false,
        });
      } catch (error) {
        return reply(message.id, { content: [{ type: "text", text: String(error) }], isError: true });
      }
    }
    default:
      return fail(message.id, -32601, `Method not found: ${message.method}`);
  }
}

async function mcp(request: Request): Promise<Response> {
  const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...CORS, ...extra },
    });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (request.method !== "POST") {
    return json(fail(null, -32000, "Use POST with a JSON-RPC 2.0 body. This server is stateless and has no event stream."), 405, { allow: "POST, OPTIONS" });
  }
  if (Number(request.headers.get("content-length") ?? 0) > MAX_BODY) return json(fail(null, -32600, "Request too large"), 413);
  const text = await request.text();
  if (text.length > MAX_BODY) return json(fail(null, -32600, "Request too large"), 413);
  let payload: Rpc | Rpc[];
  try {
    payload = JSON.parse(text);
  } catch {
    return json(fail(null, -32700, "Parse error"), 400);
  }
  const batch = Array.isArray(payload) ? payload : [payload];
  if (batch.length === 0 || batch.length > MAX_BATCH) return json(fail(null, -32600, "Invalid batch size"), 400);
  const results = batch.map(handle).filter((r) => r !== null);
  if (results.length === 0) return new Response(null, { status: 202, headers: CORS });
  return json(Array.isArray(payload) ? results : results[0]);
}

function secured(response: Response, path: string): Response {
  const headers = new Headers(response.headers);
  headers.set("x-content-type-options", "nosniff");
  headers.set("referrer-policy", "strict-origin-when-cross-origin");
  headers.set("permissions-policy", "camera=(), microphone=(), geolocation=(), interest-cohort=()");
  headers.set("cross-origin-opener-policy", "same-origin");
  headers.set("strict-transport-security", "max-age=31536000; includeSubDomains");
  headers.set("link", `<${PREFIX}/llms.txt>; rel="describedby"; type="text/plain"`);
  const type = headers.get("content-type") ?? "";
  if (type.startsWith("text/html")) {
    headers.set("content-security-policy", CSP);
    // no-transform keeps Cloudflare from injecting its analytics beacon into the page.
    headers.set("cache-control", "public, max-age=0, must-revalidate, no-transform");
  } else if (path.startsWith("/_astro/")) {
    headers.set("cache-control", "public, max-age=31536000, immutable");
  } else if (!headers.has("cache-control")) {
    headers.set("cache-control", "public, max-age=3600");
  }
  headers.append("vary", "Accept");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    let path = url.pathname;
    if (path === PREFIX) return Response.redirect(`${url.origin}${PREFIX}/${url.search}`, 301);
    if (path.startsWith(`${PREFIX}/`)) path = path.slice(PREFIX.length);

    if (path === "/mcp" || path === "/mcp/") return mcp(request);

    // The site used to be several pages. Old links land on the matching section.
    const moved = MOVED[path.replace(/\/$/, "")];
    if (moved) return Response.redirect(moved.startsWith("http") ? moved : `${url.origin}${PREFIX}/${moved}`, 301);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { allow: "GET, HEAD" } });
    }

    // An agent that asks for Markdown gets the Markdown mirror of the page.
    const accept = request.headers.get("accept") ?? "";
    if (path.endsWith("/") && accept.includes("text/markdown") && !accept.includes("text/html")) {
      const mirror = path === "/" ? "/index.md" : `${path.slice(0, -1)}.md`;
      const asset = await env.ASSETS.fetch(new Request(new URL(mirror, url.origin), request));
      if (asset.ok) {
        const headers = new Headers(asset.headers);
        headers.set("content-type", "text/markdown; charset=utf-8");
        return secured(new Response(asset.body, { status: 200, headers }), mirror);
      }
    }

    const target = new URL(path + url.search, url.origin);
    const asset = await env.ASSETS.fetch(new Request(target, request));
    return secured(asset, path);
  },
};
