#!/usr/bin/env node
// Builds the committed, dependency-free bundle an agent host runs straight from
// a git clone of this repo: dist/uc.js (the CLI) and dist/uc-mcp.js (the MCP
// server). Every library is folded in; Node is the only runtime.
//
// The output is committed on purpose. tests/plugin/bundle.test.ts rebuilds it
// and fails when the committed copy differs from source, so it cannot go stale.
import { build } from "esbuild";
import { chmodSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

//: @use-case:plugin.bundle.runs_from_clean_clone#bundler
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outArg = process.argv.indexOf("--out");
const outDir = outArg === -1 ? join(repoRoot, "dist") : resolve(process.argv[outArg + 1]);

const entries = [
  { entry: "packages/cli/src/index.ts", out: "uc.js" },
  { entry: "packages/mcp/src/index.ts", out: "uc-mcp.js" }
];

for (const { entry, out } of entries) {
  const outfile = join(outDir, out);
  await build({
    entryPoints: [join(repoRoot, entry)],
    outfile,
    bundle: true,
    platform: "node",
    format: "esm",
    target: "node22",
    // The workspace alias points at packages/core/dist (a build product); bundle
    // from source so no prior tsc run is needed.
    alias: { "@adammcarter/use-cases-core": join(repoRoot, "packages/core/src/index.ts") },
    // CommonJS libraries in the bundle (yaml, ajv) call require(); give an ESM
    // bundle a real one. The source shebang is preserved above this banner.
    banner: { js: 'import { createRequire as __ucCreateRequire } from "node:module"; const require = __ucCreateRequire(import.meta.url);' },
    legalComments: "none",
    // The core's dist fallback import is a variable specifier the bundler cannot
    // follow; the alias above makes it unreachable, so the warning is noise.
    logOverride: { "unsupported-dynamic-import": "silent" },
    logLevel: "warning"
  });
  chmodSync(outfile, 0o755);
}
//: @use-case:end plugin.bundle.runs_from_clean_clone#bundler
