// WebMCP: registers the read-only docs tools with the browser's model context, where it exists.
// The API is experimental. Everywhere else this does nothing, and the page works the same.
import { TOOLS, run, type Knowledge } from "../mcp-core";

interface ModelContext {
  registerTool?: (tool: unknown, options?: { signal?: AbortSignal }) => unknown;
  provideContext?: (context: { tools: unknown[] }) => unknown;
}

const context = (navigator as Navigator & { modelContext?: ModelContext }).modelContext;

async function init() {
  if (!context) return;
  const base = import.meta.env.BASE_URL;
  let cache: Promise<Knowledge> | undefined;
  const knowledge = () => (cache ??= fetch(`${base}knowledge.json`).then((r) => r.json() as Promise<Knowledge>));

  const tools = TOOLS.map((tool) => ({
    name: tool.name,
    description: tool.description,
    inputSchema: tool.inputSchema,
    annotations: tool.annotations,
    async execute(input: Record<string, unknown> = {}) {
      const result = run(tool.name, input, await knowledge(), location.origin);
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    },
  }));

  try {
    if (context.registerTool) {
      for (const tool of tools) await context.registerTool(tool);
    } else if (context.provideContext) {
      await context.provideContext({ tools });
    }
  } catch {
    // A duplicate registration or a context that refuses tools is not worth surfacing.
  }
}

init();
