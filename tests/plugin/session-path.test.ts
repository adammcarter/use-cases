import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const hook = join(repoRoot, "hooks/session-start");
const dirs: string[] = [];

function scratch(): string {
  const dir = mkdtempSync(join(tmpdir(), "use-cases-session-path-"));
  dirs.push(dir);
  return dir;
}

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function runHook(extraEnv: Record<string, string | undefined>) {
  const env: Record<string, string> = { ...process.env, CLAUDE_PLUGIN_ROOT: repoRoot } as Record<string, string>;
  delete env.CLAUDE_ENV_FILE;
  for (const [k, v] of Object.entries(extraEnv)) {
    if (v === undefined) delete env[k];
    else env[k] = v;
  }
  return spawnSync("bash", [hook], { encoding: "utf8", env });
}

function bootstrapContext(stdout: string): string {
  return JSON.parse(stdout).hookSpecificOutput.additionalContext as string;
}

//: @use-case:plugin.install.uc_on_path_in_session
describe("uc is a plain command inside any session", () => {
  test("bin/uc runs the bundle from any working directory", () => {
    const cwd = scratch();
    const result = spawnSync(join(repoRoot, "bin/uc"), ["version", "--json"], { cwd, encoding: "utf8" });
    expect(result.status, result.stderr).toBe(0);
    expect(JSON.parse(result.stdout).command).toBe("version");
  });

  test("with CLAUDE_ENV_FILE set the hook prints the bootstrap and exports the plugin bin on PATH", () => {
    const envFile = join(scratch(), "env.sh");
    const result = runHook({ CLAUDE_ENV_FILE: envFile });
    expect(result.status, result.stderr).toBe(0);
    expect(bootstrapContext(result.stdout)).toContain("<EXTREMELY_IMPORTANT>");
    const exported = readFileSync(envFile, "utf8");
    expect(exported).toMatch(/^export PATH="[^"]*\/bin:\$PATH"$/m);
    expect(exported).toContain(`${repoRoot}/bin`);
    // Sourcing the file must make uc resolvable.
    const probe = spawnSync("bash", ["-c", `source "${envFile}" && command -v uc && uc version --json`], { encoding: "utf8" });
    expect(probe.status, probe.stderr).toBe(0);
    expect(probe.stdout).toContain(`${repoRoot}/bin/uc`);
  });

  test("with CLAUDE_ENV_FILE unset the hook prints the bootstrap and writes nothing", () => {
    const result = runHook({ CLAUDE_ENV_FILE: undefined });
    expect(result.status, result.stderr).toBe(0);
    expect(bootstrapContext(result.stdout)).toContain("<EXTREMELY_IMPORTANT>");
    expect(result.stderr).toBe("");
  });

  test("with an unwritable CLAUDE_ENV_FILE the hook still delivers the bootstrap and names the file on stderr", () => {
    const envFile = join(scratch(), "missing-dir", "env.sh");
    const result = runHook({ CLAUDE_ENV_FILE: envFile });
    expect(result.status).toBe(0);
    expect(bootstrapContext(result.stdout)).toContain("<EXTREMELY_IMPORTANT>");
    expect(result.stderr).toContain(envFile);
    expect(existsSync(envFile)).toBe(false);
  });
});
//: @use-case:end plugin.install.uc_on_path_in_session
