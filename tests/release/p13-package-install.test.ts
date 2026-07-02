import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, readFileSync, realpathSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");

const requiredRootArtifactPaths = [
  ".agents/skills/use-case-matrix/SKILL.md",
  ".agents/skills/showcase/SKILL.md",
  ".agents/skills/walkthrough/SKILL.md",
  ".claude-plugin/plugin.json",
  ".codex-plugin/plugin.json",
  ".mcp.json",
  "bootstrap/use-case-matrix.md",
  "docs/release.md",
  "docs/security.md",
  "hosts/codex.yml",
  "packages/cli/dist/index.js",
  "packages/cli/package.json",
  "packages/core/dist/index.js",
  "packages/core/dist/schemas/v1/use-case-file.schema.json",
  "packages/core/package.json",
  "packages/mcp/dist/index.js",
  "packages/mcp/package.json",
  "plugin.json",
  "README.md",
  "CHANGELOG.md",
  "schemas/v1/use-case-file.schema.json",
  "use-cases/showcase/live.yml"
];

const forbiddenEntrySegments = [
  ".albus",
  ".Codex",
  ".cowork-receipts",
  ".DS_Store",
  ".copy-schemas.lock",
  "node_modules",
  "coverage",
  "tests",
  "src"
];

const forbiddenTextPatterns = [
  { id: "local_user_path", pattern: /\/Users\/admin\b/ },
  { id: "mac_temp_path", pattern: /\/var\/folders\/|\/private\/var\/folders\// },
  { id: "openai_key", pattern: /sk-[A-Za-z0-9_-]{20,}/ },
  { id: "github_token", pattern: /gh[pousr]_[A-Za-z0-9_]{20,}/ },
  { id: "private_key", pattern: /BEGIN (?:OPENSSH|RSA|EC|DSA) PRIVATE KEY/ }
];

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]));
}, 30_000);

describe("P13 installable root package artifact", () => {
  test("root tarball contains release-critical assets and no local/session state", () => {
    const packed = packRoot();
    const entries = tarEntries(packed.tarball);

    for (const required of requiredRootArtifactPaths) {
      expect(entries).toContain(`package/${required}`);
    }
    // `src`/`tests` are legitimate CONTENT of the example PROJECTS shipped under
    // examples/ (e.g. examples/python-pytest carries a real src/ + tests/ layout —
    // the python.pytest verifier preset mandates the tests/ path). They remain
    // forbidden everywhere else, so the repo's OWN sources/tests can never leak.
    const exampleContentSegments = new Set(["src", "tests"]);
    for (const entry of entries) {
      const parts = entry.split("/");
      const underExamples = parts.includes("examples");
      for (const forbidden of forbiddenEntrySegments) {
        if (underExamples && exampleContentSegments.has(forbidden)) {
          continue;
        }
        expect(parts).not.toContain(forbidden);
      }
    }

    const extractedRoot = extractPackageRoot(packed.tarball);
    expect(scanForbiddenText(extractedRoot)).toEqual([]);
  });

  test("root tarball installs into a clean project and runs installed CLI and MCP", () => {
    const installed = installRootTarball(packRoot().tarball);
    const installedRoot = installed.installedRoot;
    expect(installedRoot.startsWith(repoRoot)).toBe(false);

    const cli = run(process.execPath, [
      join(installedRoot, "packages/cli/dist/index.js"),
      "schema",
      "list",
      "--json"
    ], installed.consumer);
    requireSuccess(cli);
    expect(JSON.parse(cli.stdout)).toMatchObject({
      command: "schema.list",
      ok: true,
      data: {
        schemas: expect.arrayContaining([
          expect.objectContaining({ id: "https://use-case-matrix.dev/schemas/v1/use-case-file.schema.json" })
        ])
      }
    });
    expect(`${cli.stdout}\n${cli.stderr}`).not.toContain(repoRoot);

    const fixtureRoot = fixtureWorkspace("evidence-basic");
    const installedBin = run(join(installed.consumer, "node_modules/.bin/ucm"), [
      "matrix",
      "validate",
      "--repo",
      fixtureRoot,
      "--json"
    ], installed.consumer);
    requireSuccess(installedBin);
    expect(JSON.parse(installedBin.stdout)).toMatchObject({
      command: "matrix.validate",
      ok: true,
      complete: true
    });
    expect(`${installedBin.stdout}\n${installedBin.stderr}`).not.toContain(repoRoot);

    const mcp = runWithInput(
      process.execPath,
      [join(installedRoot, "packages/mcp/dist/index.js")],
      [
        JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: {
            protocolVersion: "2024-11-05",
            capabilities: {},
            clientInfo: { name: "p13-installed-root", version: "0.0.0" }
          }
        }),
        JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }),
        ""
      ].join("\n")
    );
    requireSuccess(mcp);
    expect(`${mcp.stdout}\n${mcp.stderr}`).not.toContain(repoRoot);
    expect(mcp.stdout.trim().split("\n").map((line) => JSON.parse(line))).toEqual([
      expect.objectContaining({
        id: 1,
        result: expect.objectContaining({
          serverInfo: { name: "use-case-matrix", version: "1.0.0" }
        })
      }),
      expect.objectContaining({
        id: 2,
        result: {
          tools: expect.arrayContaining([
            expect.objectContaining({ name: "matrix_validate" }),
            expect.objectContaining({ name: "showcase_request_approval" }),
            expect.objectContaining({ name: "host_doctor" })
          ])
        }
      })
    ]);
  });

  test("doctor package inspects explicit tarball and installed-root targets", () => {
    const tarball = packRoot().tarball;

    const tarballDoctor = runCli(["doctor", "package", "--tarball", tarball, "--json"]);
    requireSuccess(tarballDoctor);
    expect(JSON.parse(tarballDoctor.stdout)).toMatchObject({
      command: "doctor.package",
      ok: true,
      complete: true,
      diagnostics: [],
      data: {
        inspection_target: {
          kind: "tarball",
          path: tarball
        },
        required_paths: expect.arrayContaining([
          expect.objectContaining({ path: "packages/cli/dist/index.js", status: "present" }),
          expect.objectContaining({ path: "packages/mcp/dist/index.js", status: "present" })
        ]),
        forbidden_paths: [],
        forbidden_text: []
      }
    });

    const installed = installRootTarball(tarball);
    const installedDoctor = runCli(["doctor", "package", "--installed-root", installed.installedRoot, "--json"]);
    requireSuccess(installedDoctor);
    expect(JSON.parse(installedDoctor.stdout)).toMatchObject({
      command: "doctor.package",
      ok: true,
      complete: true,
      diagnostics: [],
      data: {
        inspection_target: {
          kind: "installed_root",
          path: installed.installedRoot
        },
        installed_smoke: {
          cli: { status: "passed" },
          mcp: { status: "passed" }
        }
      }
    });
  });
});

function packRoot(): { tarball: string; files: Array<{ path: string }> } {
  const packDir = mkdtempSync(join(tmpdir(), "use-case-matrix-root-pack-"));
  const result = run("corepack", ["pnpm", "pack", "--json", "--pack-destination", packDir]);
  requireSuccess(result);
  const payload = JSON.parse(result.stdout) as { filename: string; files: Array<{ path: string }> };
  return { tarball: payload.filename, files: payload.files };
}

function tarEntries(tarball: string): string[] {
  const result = run("tar", ["-tf", tarball]);
  requireSuccess(result);
  return result.stdout.trim().split("\n").filter(Boolean);
}

function extractPackageRoot(tarball: string): string {
  const extractDir = mkdtempSync(join(tmpdir(), "use-case-matrix-root-extract-"));
  const result = run("tar", ["-xzf", tarball, "-C", extractDir]);
  requireSuccess(result);
  const packageRoot = join(extractDir, "package");
  if (!existsSync(packageRoot)) {
    throw new Error(`tarball did not extract package root: ${tarball}`);
  }
  return packageRoot;
}

function installRootTarball(tarball: string): { consumer: string; installedRoot: string } {
  const consumer = mkdtempSync(join(tmpdir(), "use-case-matrix-root-consumer-"));
  writeFileSync(join(consumer, "package.json"), JSON.stringify({ type: "module", dependencies: {} }, null, 2));
  requireSuccess(run("npm", ["install", "--cache", npmCacheDir(), "--no-audit", "--no-fund", tarball], consumer));
  return {
    consumer,
    installedRoot: realpathSync(join(consumer, "node_modules", "use-case-matrix"))
  };
}

function npmCacheDir(): string {
  return mkdtempSync(join(stableCacheRoot(), "use-case-matrix-npm-cache-"));
}

function stableCacheRoot(): string {
  return process.platform === "darwin" ? "/tmp" : tmpdir();
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-case-matrix-installed-fixture-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function scanForbiddenText(root: string): Array<{ path: string; pattern: string }> {
  const hits: Array<{ path: string; pattern: string }> = [];
  for (const file of listFiles(root)) {
    if (!isTextFile(file)) {
      continue;
    }
    const rel = file.slice(root.length + 1).replaceAll("\\", "/");
    const text = readFileSync(file, "utf8");
    for (const forbidden of forbiddenTextPatterns) {
      if (forbidden.pattern.test(text)) {
        hits.push({ path: rel, pattern: forbidden.id });
      }
    }
  }
  return hits;
}

function listFiles(root: string): string[] {
  const stat = statSync(root);
  if (!stat.isDirectory()) {
    return [root];
  }
  return readdirSync(root).flatMap((entry) => listFiles(join(root, entry)));
}

function isTextFile(path: string): boolean {
  return /\.(?:cjs|js|json|md|mjs|txt|yml|yaml)$/.test(basename(path));
}

function runCli(args: string[]): SpawnSyncReturns<string> {
  return run(process.execPath, ["packages/cli/dist/index.js", ...args]);
}

function run(command: string, args: string[], cwd = repoRoot): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: childEnv()
  });
}

function runWithInput(command: string, args: string[], input: string, cwd = repoRoot): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd,
    input,
    encoding: "utf8",
    env: childEnv()
  });
}

function childEnv(): NodeJS.ProcessEnv {
  return {
    ...process.env,
    COREPACK_ENABLE_DOWNLOAD_PROMPT: "0",
    NODE_PATH: ""
  };
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
