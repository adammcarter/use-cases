# Release Checklist

Run the production release gate from the repository root:

```bash
node scripts/release-gate.mjs
```

The gate is intentionally sequential. Do not run `build` concurrently with
`test`; tests import built workspace package outputs.

Before release, inspect:

- CI runs `node scripts/release-gate.mjs` on Node 22.
- `doctor package` is complete and has no diagnostics. By default it builds and
  inspects the real root package tarball, not just the checkout.
- For external artifacts, use `doctor package --tarball <path> --json`.
- For installed artifacts, use `doctor package --installed-root <path> --json`;
  this also runs installed CLI and MCP smoke checks.
- Root package contents include `.agents/skills`, `.codex-plugin/plugin.json`,
  `.mcp.json`, built CLI/MCP/Core `dist`, schemas, docs, examples, and use cases.
- Root package contents omit tests, TypeScript source, local session state,
  build locks, `node_modules`, and coverage output.
- Host docs do not claim verified support unless evidence IDs exist.
- A real showcase run on this plugin is recorded if the release changes user
  workflow.
