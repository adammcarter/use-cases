#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const packDir = mkdtempSync(join(tmpdir(), "use-cases-plugin-release-pack-"));

const steps = [
  ["corepack pnpm install --frozen-lockfile", "corepack", ["pnpm", "install", "--frozen-lockfile"]],
  ["corepack pnpm typecheck", "corepack", ["pnpm", "typecheck"]],
  ["corepack pnpm build", "corepack", ["pnpm", "build"]],
  ["corepack pnpm test", "corepack", ["pnpm", "test"]],
  ["corepack pnpm cli -- doctor package --json", "corepack", ["pnpm", "cli", "--", "doctor", "package", "--json"]],
  ["corepack pnpm cli -- matrix validate --repo . --json", "corepack", ["pnpm", "cli", "--", "matrix", "validate", "--repo", ".", "--json"]],
  ["corepack pnpm cli -- matrix list --repo . --json", "corepack", ["pnpm", "cli", "--", "matrix", "list", "--repo", ".", "--json"]],
  // README guard: the documented quickstart uses the HUMAN (bare, no --json) form.
  // Run the exact commands so a regression in the human path fails the release
  // gate instead of shipping a quickstart that errors (the arch review's #1).
  ["corepack pnpm cli -- matrix validate --repo . (human)", "corepack", ["pnpm", "cli", "--", "matrix", "validate", "--repo", "."]],
  ["corepack pnpm cli -- matrix list --repo . (human)", "corepack", ["pnpm", "cli", "--", "matrix", "list", "--repo", "."]],
  ["corepack pnpm cli -- plan showcase --repo . --max-items 3 (human)", "corepack", ["pnpm", "cli", "--", "plan", "showcase", "--repo", ".", "--max-items", "3"]],
  [
    "corepack pnpm pack --json --pack-destination",
    "corepack",
    ["pnpm", "pack", "--json", "--pack-destination", packDir]
  ]
];

for (const [label, command, args] of steps) {
  process.stdout.write(`\n$ ${label}${label.endsWith("--pack-destination") ? ` ${packDir}` : ""}\n`);
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });

  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }
  if (result.status !== 0) {
    process.stderr.write(`release gate failed at: ${label}\n`);
    process.exit(result.status ?? 1);
  }
}

process.stdout.write("\nrelease gate passed\n");
