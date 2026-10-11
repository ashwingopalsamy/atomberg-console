// apps.ashwingopalsamy.in: the root of the hostname. It serves the files that only count at the origin root
// (robots, sitemap index, llms index, well-known) and hands each app's path to that app's Worker.
import apps from "../apps.json";

type Fetcher = { fetch(request: Request): Promise<Response> };
type Env = { ASSETS: Fetcher } & Record<string, Fetcher>;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    for (const app of apps.apps) {
      const prefix = `/${app.slug}`;
      if (url.pathname === prefix) return Response.redirect(`${url.origin}${prefix}/${url.search}`, 301);
      if (url.pathname.startsWith(`${prefix}/`)) return env[app.binding].fetch(request);
    }
    const response = await env.ASSETS.fetch(request);
    const headers = new Headers(response.headers);
    headers.set("x-content-type-options", "nosniff");
    headers.set("referrer-policy", "strict-origin-when-cross-origin");
    headers.set("strict-transport-security", "max-age=31536000; includeSubDomains");
    if ((headers.get("content-type") ?? "").startsWith("text/html")) {
      headers.set("cache-control", "public, max-age=300, no-transform");
      headers.set("content-security-policy", "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    }
    return new Response(response.body, { status: response.status, headers });
  },
};
