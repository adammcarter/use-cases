# Release Checklist

Run these from the repository root after `pnpm install`:

```bash
pnpm typecheck
pnpm build
pnpm test
pnpm pack --dry-run
pnpm cli -- doctor package --json
```

Before release, inspect:

- `doctor package` is complete and has no diagnostics.
- Root package dry-run includes `.agents/skills`, `.codex-plugin/plugin.json`,
  `.mcp.json`, built CLI/MCP/Core `dist`, schemas, docs, examples, and use cases.
- Root package dry-run omits tests, TypeScript source, local session state,
  build locks, `node_modules`, and coverage output.
- Host docs do not claim verified support unless evidence IDs exist.
- A real showcase run on this plugin is recorded if the release changes user
  workflow.
