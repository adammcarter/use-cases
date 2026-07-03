import { spawnSync } from "node:child_process";
import { createPrivateKey, createPublicKey } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";

// Subprocess tests for `ucm keygen` (Task 3, 0.1.0): the opt-in signed tier's
// keypair generator. It prints (default) or writes (--out) an ed25519 keypair in
// the PEM formats prove/--public-key consume, never writes into the repo tree,
// carries a loud CI-only warning, and (with --ci github) emits a ready-to-paste
// GitHub release-workflow snippet.

const repoRoot = resolve(import.meta.dirname, "../..");
const tmpDirs: string[] = [];

function tmpDir(prefix: string): string {
  const dir = mkdtempSync(join(tmpdir(), prefix));
  tmpDirs.push(dir);
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

describe("ucm keygen (opt-in signed tier)", () => {
  test("--json prints an inline ed25519 keypair with a CI-only warning", () => {
    const res = runCli(["keygen", "--json"]);

    expect(res.status).toBe(0);
    const payload = JSON.parse(res.stdout);
    expect(payload.command).toBe("markers.keygen");
    expect(payload.ok).toBe(true);

    // Inline PEMs in the exact formats prove/--public-key consume.
    expect(typeof payload.data.private_key).toBe("string");
    expect(typeof payload.data.public_key).toBe("string");
    expect(createPrivateKey(payload.data.private_key).asymmetricKeyType).toBe("ed25519");
    expect(createPublicKey(payload.data.public_key).asymmetricKeyType).toBe("ed25519");

    // A loud, machine-readable "private key belongs only in CI secrets" warning.
    const warned =
      payload.diagnostics.some((d: { code: string }) => d.code === "keygen.private_key_is_secret") ||
      JSON.stringify(payload.data).toLowerCase().includes("ci secret");
    expect(warned).toBe(true);
    expect(res.stderr).not.toMatch(STACK_TRACE);
  });

  test("--out writes the keypair to disk and returns the file paths", () => {
    const outDir = tmpDir("ucm-keygen-out-");
    const res = runCli(["keygen", "--out", outDir, "--json"]);

    expect(res.status).toBe(0);
    const payload = JSON.parse(res.stdout);
    expect(payload.ok).toBe(true);

    const privatePath = payload.data.private_key_path as string;
    const publicPath = payload.data.public_key_path as string;
    expect(existsSync(privatePath)).toBe(true);
    expect(existsSync(publicPath)).toBe(true);
    expect(createPrivateKey(readFileSync(privatePath, "utf8")).asymmetricKeyType).toBe("ed25519");
    expect(createPublicKey(readFileSync(publicPath, "utf8")).asymmetricKeyType).toBe("ed25519");

    // The private PEM is NOT echoed inline when written to a file (avoid leaking
    // it into logs); the path is enough.
    expect(payload.data.private_key).toBeUndefined();
  });

  test("--out refuses to write inside --repo (private key must not land in the tree)", () => {
    const repoDir = tmpDir("ucm-keygen-repo-");
    const insideRepo = join(repoDir, "keys");
    const res = runCli(["keygen", "--repo", repoDir, "--out", insideRepo, "--json"]);

    expect(res.status).not.toBe(0);
    const payload = JSON.parse(res.stdout);
    expect(payload.ok).toBe(false);
    expect(payload.diagnostics[0].code).toBe("keygen.out_inside_repo");
    expect(existsSync(join(insideRepo, "ci-signing-key.pem"))).toBe(false);
    expect(res.stderr).not.toMatch(STACK_TRACE);
  });

  test("--ci github emits a release-workflow snippet using id-token OIDC and no token", () => {
    const res = runCli(["keygen", "--ci", "github", "--json"]);

    expect(res.status).toBe(0);
    const payload = JSON.parse(res.stdout);
    expect(payload.ok).toBe(true);

    const snippet = payload.data.ci_snippet as string;
    expect(typeof snippet).toBe("string");
    expect(snippet).toContain("release.yml");
    expect(snippet).toContain("id-token");
    // A GitHub *secret* holds the private key; the workflow never embeds a token.
    expect(snippet.toLowerCase()).toContain("secret");
    expect(snippet).not.toMatch(/ghp_[A-Za-z0-9]/);
  });
});
