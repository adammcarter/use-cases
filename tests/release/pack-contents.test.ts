import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");

/**
 * Supply-chain guard: every publishable package tarball must ship ONLY its built
 * artifacts (dist JS + d.ts, shipped schemas, package.json, README, LICENSE) and
 * must never leak source, tests, build config, local state, or secrets. This is
 * the last line of defence before an artifact reaches npm.
 */

interface PackageSpec {
  /** pnpm `--filter` target. */
  filter: string;
  /** Tarball filename produced by `pnpm pack` (scope stripped, slash -> dash). */
  tarball: string;
  /** Paths (relative to the package root) that MUST be present in the tarball. */
  requiredIncludes: string[];
}

const packages: PackageSpec[] = [
  {
    filter: "@use-cases-plugin/core",
    tarball: "use-cases-plugin-core-1.0.0.tgz",
    requiredIncludes: [
      "dist/index.js",
      "dist/index.d.ts",
      "dist/schemas/v1/use-case-file.schema.json",
      "package.json",
      "README.md",
      "LICENSE"
    ]
  },
  {
    filter: "@use-cases-plugin/cli",
    tarball: "use-cases-plugin-cli-1.0.0.tgz",
    requiredIncludes: [
      "dist/index.js",
      "dist/index.d.ts",
      "package.json",
      "README.md",
      "LICENSE"
    ]
  },
  {
    filter: "@use-cases-plugin/mcp",
    tarball: "use-cases-plugin-mcp-1.0.0.tgz",
    requiredIncludes: [
      "dist/index.js",
      "dist/index.d.ts",
      "dist/tools.js",
      "package.json",
      "README.md",
      "LICENSE"
    ]
  }
];

/**
 * Predicates that classify a tarball entry (relative to the package root) as a
 * supply-chain leak. Any match is a hard failure.
 */
const forbiddenRules: Array<{ id: string; matches: (relPath: string) => boolean }> = [
  { id: "typescript_source", matches: (p) => segments(p).includes("src") },
  { id: "test_file", matches: (p) => /\.test\.[^/]+$/.test(basename(p)) },
  { id: "test_directory", matches: (p) => segments(p).includes("test") || segments(p).includes("tests") },
  { id: "test_fixtures", matches: (p) => segments(p).includes("fixtures") || segments(p).includes("__fixtures__") },
  { id: "tsconfig", matches: (p) => /^tsconfig.*\.json$/.test(basename(p)) },
  { id: "tsbuildinfo", matches: (p) => p.endsWith(".tsbuildinfo") },
  { id: "use_cases_state", matches: (p) => segments(p).includes(".use-cases") },
  { id: "private_key", matches: (p) => /\.(pem|key|p12|pfx)$/.test(basename(p)) },
  { id: "dotenv", matches: (p) => /^\.env(\..+)?$/.test(basename(p)) },
  { id: "node_modules", matches: (p) => segments(p).includes("node_modules") },
  { id: "copy_schemas_lock", matches: (p) => segments(p).includes(".copy-schemas.lock") }
];

function segments(relPath: string): string[] {
  return relPath.split("/").filter(Boolean);
}

let packDir: string;

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]));
  packDir = mkdtempSync(join(stableTmpRoot(), "use-cases-plugin-pack-contents-"));
}, 120_000);

describe("release pack contents", () => {
  for (const spec of packages) {
    test(`${spec.filter} tarball ships only built artifacts and no source/secrets`, () => {
      const entries = packEntries(spec);

      // Sanity: a non-empty, dist-bearing tarball.
      expect(entries.length).toBeGreaterThan(0);
      expect(entries.some((entry) => entry.startsWith("dist/"))).toBe(true);

      // INCLUDES — every required artifact is present.
      for (const required of spec.requiredIncludes) {
        expect(entries, `${spec.filter} tarball is missing ${required}`).toContain(required);
      }

      // EXCLUDES — no entry may match a forbidden rule.
      const leaks = entries.flatMap((entry) =>
        forbiddenRules.filter((rule) => rule.matches(entry)).map((rule) => ({ entry, rule: rule.id }))
      );
      expect(leaks, `forbidden entries in ${spec.filter} tarball: ${JSON.stringify(leaks)}`).toEqual([]);
    });
  }
});

function packEntries(spec: PackageSpec): string[] {
  requireSuccess(
    run("corepack", ["pnpm", "--filter", spec.filter, "pack", "--pack-destination", packDir])
  );
  const tarball = join(packDir, spec.tarball);
  const listing = run("tar", ["-tf", tarball]);
  requireSuccess(listing);
  return listing.stdout
    .trim()
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((entry) => entry.replace(/^package\//, ""))
    .filter((entry) => entry.length > 0 && !entry.endsWith("/"));
}

function stableTmpRoot(): string {
  return process.platform === "darwin" ? "/tmp" : tmpdir();
}

function run(command: string, args: string[], cwd = repoRoot): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function requireSuccess(result: SpawnSyncReturns<string>): void {
  if (result.status !== 0) {
    throw new Error(
      [
        `command failed with status ${result.status}`,
        `stdout:\n${result.stdout}`,
        `stderr:\n${result.stderr}`
      ].join("\n")
    );
  }
}
