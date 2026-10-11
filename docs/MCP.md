# MCP

There are three surfaces. Only the first two exist today.

| Surface | What it is | Status |
|---|---|---|
| **WebMCP** | The project site registers read-only tools with `navigator.modelContext` in browsers that support it. | live |
| **Remote MCP** | `https://apps.ashwingopalsamy.in/atomberg-console/mcp`, streamable HTTP, stateless, read-only. Same tools as WebMCP. | live |
| **App MCP** | The app itself exposes your devices to a local agent. | designed, not built |

## Site tools (WebMCP and remote)

| Tool | Returns |
|---|---|
| `search_docs(query, limit?)` | matching pages with a snippet and URL |
| `get_faq(topic?)` | questions and answers from `docs/faq.json` |
| `get_install_steps(method?)` | `homebrew`, `dmg` or `source` steps |
| `get_privacy_policy()` | the hosts and ports the app may contact, and what it stores |
| `get_call_budget()` | what each action costs against the 100 calls a day |
| `get_release()` | version, date, notes and the release URL |

All tools are read-only, take no credentials, and return the same text as the pages.

## App MCP contract (not implemented)

Rules, because the app's promise is that it calls no one:

- **Local only.** stdio transport, started by the agent host. No listening port.
- **Opt-in.** Off by default; one switch in Settings, and a visible "agent connected" state while a session runs.
- **Read-only first.**

| Tool | Returns |
|---|---|
| `list_devices()` | id, name, kind, model, online, transport (`local`, `cloud`, `offline`) |
| `get_state(device_id)` | power, speed, timer, light, last seen |
| `get_call_budget()` | calls used and left today |
| `check_local_network()` | runs the manual local check, returns what it found |

- Control tools (`set_power`, `set_speed`) come later, each needing approval in the app once per session.
- Everything passes `NetworkPolicy` and `scripts/check-egress.sh` unchanged: the MCP server adds no network
  destination.
