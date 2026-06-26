#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const packDir = mkdtempSync(join(tmpdir(), "presentation-skills-release-pack-"));

const steps = [
  ["corepack pnpm install --frozen-lockfile", "corepack", ["pnpm", "install", "--frozen-lockfile"]],
  ["corepack pnpm typecheck", "corepack", ["pnpm", "typecheck"]],
  ["corepack pnpm build", "corepack", ["pnpm", "build"]],
  ["corepack pnpm test", "corepack", ["pnpm", "test"]],
  ["corepack pnpm cli -- doctor package --json", "corepack", ["pnpm", "cli", "--", "doctor", "package", "--json"]],
  ["corepack pnpm cli -- matrix validate --repo . --json", "corepack", ["pnpm", "cli", "--", "matrix", "validate", "--repo", ".", "--json"]],
  ["corepack pnpm cli -- matrix list --repo . --json", "corepack", ["pnpm", "cli", "--", "matrix", "list", "--repo", ".", "--json"]],
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
