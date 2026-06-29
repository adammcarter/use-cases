import { cpSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { beforeAll, describe, expect, test } from "vitest";
import { isMissingCoreModule, MISSING_BUILD_MESSAGE } from "../../../packages/ucm-cli/src/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]));
}, 60_000);

function run(command: string, args: string[]): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function runCli(args: string[]): SpawnSyncReturns<string> {
  return run("node", ["packages/ucm-cli/dist/index.js", ...args]);
}

function requireSuccess(result: SpawnSyncReturns<string>): void {
  if (result.status !== 0) {
    throw new Error(
      [`command failed with status ${result.status}`, `stdout:\n${result.stdout}`, `stderr:\n${result.stderr}`].join("\n")
    );
  }
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-cases-plugin-ergo-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

describe("CLI help and usage discoverability", () => {
  test("--help prints a usage envelope listing the available commands", () => {
    const result = runCli(["--help"]);
    expect(result.status).toBe(0);
    expect(result.stderr).toBe("");
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({ command: "help", ok: true, complete: true });
    expect(Array.isArray(payload.data.commands)).toBe(true);
    const names = payload.data.commands.map((entry: { name: string }) => entry.name);
    expect(names).toContain("matrix upsert");
    expect(names).toContain("evidence record");
  });

  test("a bare invocation also prints the usage envelope", () => {
    const result = runCli([]);
    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload.command).toBe("help");
    expect(payload.data.commands.length).toBeGreaterThan(0);
  });

  test("subcommand --help scopes to that command and lists its flags", () => {
    const result = runCli(["matrix", "upsert", "--help"]);
    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload.command).toBe("help");
    const names = payload.data.commands.map((entry: { name: string }) => entry.name);
    expect(names.every((name: string) => name.startsWith("matrix"))).toBe(true);
    const upsert = payload.data.commands.find((entry: { name: string }) => entry.name === "matrix upsert");
    expect(upsert).toBeDefined();
    const flags = upsert.flags.map((flag: { flag: string }) => flag.flag).join(" ");
    expect(flags).toContain("--use-case-file");
    expect(flags).toContain("--use-case-json");
  });

  test("an unrecognized command prints scoped usage instead of a cryptic hint", () => {
    const result = runCli(["matrix", "bogus"]);
    expect(result.status).toBe(2);
    const payload = JSON.parse(result.stdout);
    expect(payload.command).toBe("help");
    expect(payload.ok).toBe(false);
    expect(payload.diagnostics).toEqual([
      expect.objectContaining({ code: "command.unknown" })
    ]);
    const names = payload.data.commands.map((entry: { name: string }) => entry.name);
    expect(names.every((name: string) => name.startsWith("matrix"))).toBe(true);
  });
});

describe("missing build hint", () => {
  test("ERR_MODULE_NOT_FOUND is recognized and the hint mentions pnpm build", () => {
    const error = Object.assign(new Error("Cannot find module '../../ucm-core/dist/index.js'"), {
      code: "ERR_MODULE_NOT_FOUND"
    });
    expect(isMissingCoreModule(error)).toBe(true);
    expect(isMissingCoreModule(new Error("unrelated"))).toBe(false);
    expect(MISSING_BUILD_MESSAGE).toContain("pnpm build");
  });
});

describe("matrix upsert --use-case-file", () => {
  const useCase = {
    id: "auth.login.password_reset",
    title: "Password reset entry point",
    lifecycle: "planned",
    value_tier: "supporting",
    journey_role: "alternate",
    usage_frequency: "occasional",
    tags: ["auth", "login"]
  };

  test("reads the use case from a file (happy path)", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const useCasePath = join(workspaceRoot, "new-use-case.json");
    writeFileSync(useCasePath, JSON.stringify(useCase));
    const result = runCli([
      "matrix",
      "upsert",
      "--repo",
      workspaceRoot,
      "--file",
      "use-cases/auth-login.yml",
      "--use-case-file",
      useCasePath,
      "--json"
    ]);
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "matrix.upsert",
      ok: true,
      complete: true,
      data: { operation: "upsert", status: "created", use_case_id: useCase.id }
    });
  });

  test("reports a clear diagnostic when the file is missing", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const result = runCli([
      "matrix",
      "upsert",
      "--repo",
      workspaceRoot,
      "--file",
      "use-cases/auth-login.yml",
      "--use-case-file",
      join(workspaceRoot, "does-not-exist.json"),
      "--json"
    ]);
    expect(result.status).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "matrix.upsert",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "matrix.use_case_file_unreadable" })]
    });
  });

  test("reports invalid JSON in the file", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const useCasePath = join(workspaceRoot, "bad.json");
    writeFileSync(useCasePath, "{ not json");
    const result = runCli([
      "matrix",
      "upsert",
      "--repo",
      workspaceRoot,
      "--file",
      "use-cases/auth-login.yml",
      "--use-case-file",
      useCasePath,
      "--json"
    ]);
    expect(result.status).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "matrix.upsert",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "matrix.mutation_invalid_json" })]
    });
  });
});

describe("evidence record surfaces assurance class", () => {
  test("a self-reported observation reports the weakest (reported) assurance tier", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const result = runCli([
      "evidence",
      "record",
      "--repo",
      workspaceRoot,
      "--use-case",
      "showcase.live.golden",
      "--kind",
      "manual_observation",
      "--result",
      "pass",
      "--json"
    ]);
    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({ command: "evidence.record", ok: true });
    const assurance = payload.diagnostics.find(
      (diagnostic: { code: string }) => diagnostic.code === "evidence.assurance_class"
    );
    expect(assurance).toBeDefined();
    expect(assurance.message).toContain("reported");
  });
});
