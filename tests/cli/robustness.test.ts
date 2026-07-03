import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";

// Subprocess CLI robustness tests covering the v1.0.1 dogfood findings: every
// failure path must render the standard ok:false JSON envelope (never a bare
// Node stack trace), unknown flags must be rejected, and a non-existent --repo
// must be surfaced rather than silently reported as valid.

const repoRoot = resolve(import.meta.dirname, "../..");
const tmpDirs: string[] = [];

function tmpWorkspace(files: Record<string, string>): string {
  const dir = mkdtempSync(join(tmpdir(), "ucm-robust-"));
  tmpDirs.push(dir);
  for (const [name, content] of Object.entries(files)) {
    writeFileSync(join(dir, name), content);
  }
  return dir;
}

afterEach(() => {
  while (tmpDirs.length > 0) {
    rmSync(tmpDirs.pop() as string, { recursive: true, force: true });
  }
});

function runCli(args: string[]) {
  return spawnSync("node", ["packages/cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

const STACK_TRACE = /UseCasesPluginError|\bat .*:\d+:\d+/;

describe("CLI robustness (v1.0.1 dogfood fixes)", () => {
  test("malformed use-cases.yml yields an ok:false envelope, not a stack trace", () => {
    const dir = tmpWorkspace({ "use-cases.yml": "this is: not valid: [[[\n" });
    const res = runCli(["matrix", "validate", "--repo", dir, "--json"]);

    expect(res.status).not.toBe(0);
    expect(res.stdout.trim().length).toBeGreaterThan(0);
    const payload = JSON.parse(res.stdout);
    expect(payload.command).toContain("matrix");
    expect(payload.ok).toBe(false);
    expect(payload.diagnostics.length).toBeGreaterThan(0);
    expect(payload.diagnostics[0].code).toBe("workspace_config.parse_error");
    expect(res.stderr).not.toMatch(STACK_TRACE);
  });

  test("unknown flags are rejected with exit 2, not silently ignored", () => {
    const res = runCli([
      "matrix",
      "list",
      "--repo",
      "tests/fixtures/workspaces/minimal-valid",
      "--totally-bogus-flag",
      "--json"
    ]);

    expect(res.status).toBe(2);
    const payload = JSON.parse(res.stdout);
    expect(payload.ok).toBe(false);
    expect(payload.diagnostics.some((d: { message: string }) => d.message.includes("--totally-bogus-flag"))).toBe(true);
    expect(res.stderr).not.toMatch(STACK_TRACE);
  });

  test("matrix validate on a non-existent --repo surfaces a diagnostic", () => {
    const res = runCli(["matrix", "validate", "--repo", "/no/such/path/ucm-nope", "--json"]);

    const payload = JSON.parse(res.stdout);
    // Either an error envelope or at least a diagnostic — but NOT a clean valid:true.
    const saysMissing = payload.diagnostics.some((d: { code: string }) =>
      d.code.includes("workspace") || d.code.includes("repo") || d.code.includes("path")
    );
    expect(saysMissing).toBe(true);
    expect(res.stderr).not.toMatch(STACK_TRACE);
  });

  test("prove with a malformed signing key returns a clean envelope, not an OpenSSL crash", () => {
    const dir = mkdtempSync(join(tmpdir(), "ucm-provekey-"));
    tmpDirs.push(dir);
    expect(runCli(["init", "--repo", dir]).status).toBe(0);

    const res = spawnSync(
      "node",
      ["packages/cli/dist/index.js", "prove", "--repo", dir, "--all", "--signing-key-env", "UCM_TEST_BADKEY", "--json"],
      { cwd: repoRoot, encoding: "utf8", env: { ...process.env, UCM_TEST_BADKEY: "not-a-real-key", COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" } }
    );

    expect(res.status).not.toBe(0);
    const payload = JSON.parse(res.stdout);
    expect(payload.ok).toBe(false);
    expect(payload.diagnostics[0].code).toBe("signing_key.invalid");
    expect(res.stderr).not.toMatch(STACK_TRACE);
  });

  test("bind --register-existing infers explicit mode (no --mode required)", () => {
    const dir = mkdtempSync(join(tmpdir(), "ucm-bindreg-"));
    tmpDirs.push(dir);
    // The shipped pytest example has pre-marked code + a matching row.
    cpSync(join(repoRoot, "examples/python-pytest"), dir, { recursive: true });

    const res = runCli([
      "bind",
      "--row",
      "example.checkout.apply_coupon",
      "--file",
      "src/coupon.py",
      "--register-existing",
      "--repo",
      dir,
      "--json"
    ]);

    const payload = JSON.parse(res.stdout);
    // Must NOT fail with the "Missing … --mode" error — --register-existing implies explicit.
    expect(payload.diagnostics.every((d: { message: string }) => !d.message.includes("--mode"))).toBe(true);
    expect(payload.ok).toBe(true);
    expect(res.stderr).not.toMatch(STACK_TRACE);
  });
});
