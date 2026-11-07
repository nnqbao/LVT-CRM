# Agent notes (Cursor Cloud / Background Agents)

This repo ships **project** Cursor helpers under `.cursor/` so Cloud Agents (which do **not** see your Mac Mini `~/.cursor`) still get useful context.

## What is committed vs local-only

| Artifact | Commit? | Why |
|----------|---------|-----|
| `.cursor/rules/graphify.mdc` | yes | Soft graph-first guidance |
| `.cursor/rules/ponytail.mdc` | yes | Simplest-diff coding style (rule-only; no hooks) |
| `.cursor/skills/defuddle/` | yes | Token-saving web→markdown |
| `.cursor/mcp.json` (CodeGraph) | yes (optional) | Project MCP hint; **Cloud Agents still need the same server enabled in [cursor.com/agents](https://cursor.com/agents) MCP dropdown** — project `mcp.json` is not a reliable cloud-only config surface |
| `.codegraph/` | **no** (gitignored) | Rebuild per VM; LVT-scale indexes are tens of MB |
| `graphify-out/` | **no** (gitignored) | Rebuild with `graphify update .` when needed |

## CodeGraph (preferred structural navigation when MCP is live)

1. Ensure index exists (idempotent):

```bash
npx -y @colbymchenry/codegraph init -y
```

2. Prefer MCP tools `codegraph_explore` / related once the server is connected.
3. If MCP is **not** available in this Cloud Agent session (common until dashboard MCP is enabled), fall back to CLI:

```bash
npx -y @colbymchenry/codegraph explore "<question>"
npx -y @colbymchenry/codegraph context "<task>"
```

Do **not** commit `.codegraph/`.

## Graphify (file-based graph; no MCP required)

When `graphify-out/graph.json` exists, prefer `graphify query|path|explain` (see `.cursor/rules/graphify.mdc`).
Otherwise build once if the CLI is present:

```bash
# install once per VM if needed
uv tool install graphifyy   # or: pipx install graphifyy
graphify update .
```

If install is too heavy for the task, skip and use normal search — do not block.

## Ponytail

Always-on via `.cursor/rules/ponytail.mdc`. Cloud does not get Mac Mini `hooks.json` mode switching; the rule text is enough.

## Defuddle

For reading web docs, prefer `/defuddle` skill or `npx -y defuddle parse <url> --md` over dumping raw HTML.

- Machine-local values (Convex ports, compose project name) live only in the untracked `infra/convex-local/.env` of each checkout (template `infra/convex-local/.env.example`, registry `~/ops/docs/convex-ports.md`). Never write a port number or per-checkout name into a tracked file (`tests/machine-local-config.test.mjs`). Never use 3210/3211/6791 (another project).
