// apps.ashwingopalsamy.in: the root of the hostname. It serves the files that only count at the origin root
// (robots, sitemaps, llms, icons, well-known), hands each app's path to that app's Worker, and gives the root page
// the same headers and Markdown negotiation the apps have.
import apps from "../apps.json";

type Fetcher = { fetch(request: Request): Promise<Response> };
type Env = { ASSETS: Fetcher } & Record<string, Fetcher>;

const CSP = [
  "default-src 'none'",
  "style-src 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self'",
  "manifest-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

function secured(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("x-content-type-options", "nosniff");
  headers.set("referrer-policy", "strict-origin-when-cross-origin");
  headers.set("permissions-policy", "camera=(), microphone=(), geolocation=(), interest-cohort=()");
  headers.set("cross-origin-opener-policy", "same-origin");
  headers.set("strict-transport-security", "max-age=31536000; includeSubDomains");
  headers.set("link", '</llms.txt>; rel="describedby"; type="text/plain"');
  if ((headers.get("content-type") ?? "").startsWith("text/html")) {
    headers.set("content-security-policy", CSP);
    // no-transform keeps Cloudflare from injecting its analytics beacon into the page.
    headers.set("cache-control", "public, max-age=300, no-transform");
  } else if (!headers.has("cache-control")) {
    headers.set("cache-control", "public, max-age=3600");
  }
  headers.append("vary", "Accept");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    for (const app of apps.apps) {
      // External apps have no binding: they are served from their own host, so there is nothing to route to here.
      if (!app.binding) continue;
      const prefix = `/${app.slug}`;
      if (url.pathname === prefix) return Response.redirect(`${url.origin}${prefix}/${url.search}`, 301);
      if (url.pathname.startsWith(`${prefix}/`)) return env[app.binding].fetch(request);
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { allow: "GET, HEAD" } });
    }

    // An agent that asks for Markdown gets the Markdown mirror of the page.
    const accept = request.headers.get("accept") ?? "";
    if (url.pathname === "/" && accept.includes("text/markdown") && !accept.includes("text/html")) {
      const mirror = await env.ASSETS.fetch(new Request(new URL("/index.md", url.origin), request));
      if (mirror.ok) {
        const headers = new Headers(mirror.headers);
        headers.set("content-type", "text/markdown; charset=utf-8");
        return secured(new Response(mirror.body, { status: 200, headers }));
      }
    }

    return secured(await env.ASSETS.fetch(request));
  },
};
