import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
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

describe("use-cases is a plain command inside any session", () => {
  test("bin/use-cases runs the resolved runtime from any working directory", () => {
    const cwd = scratch();
    const result = spawnSync(join(repoRoot, "bin/use-cases"), ["version", "--json"], { cwd, encoding: "utf8" });
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
    // Sourcing the file must make use-cases resolvable.
    const probe = spawnSync("bash", ["-c", `source "${envFile}" && command -v use-cases && use-cases version --json`], { encoding: "utf8" });
    expect(probe.status, probe.stderr).toBe(0);
    expect(probe.stdout).toContain(`${repoRoot}/bin/use-cases`);
  });

  test("with CLAUDE_ENV_FILE unset the hook prints the bootstrap and writes nothing", () => {
    const result = runHook({ CLAUDE_ENV_FILE: undefined });
    expect(result.status, result.stderr).toBe(0);
    expect(bootstrapContext(result.stdout)).toContain("<EXTREMELY_IMPORTANT>");
    expect(result.stderr).toBe("");
  });

  test("the bootstrap ends by naming the absolute path of bin/use-cases on every host", () => {
    for (const extra of [{ CLAUDE_ENV_FILE: undefined }, { COPILOT_CLI: "1" }]) {
      const result = runHook(extra);
      expect(result.status, result.stderr).toBe(0);
      const ctx = "hookSpecificOutput" in JSON.parse(result.stdout)
        ? bootstrapContext(result.stdout)
        : (JSON.parse(result.stdout).additionalContext as string);
      expect(ctx).toMatch(new RegExp(`use-cases .*${repoRoot.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}/bin/use-cases`));
    }
  });

  test("with an unwritable CLAUDE_ENV_FILE the hook still delivers the bootstrap and names the file on stderr", () => {
    const envFile = join(scratch(), "missing-dir", "env.sh");
    const result = runHook({ CLAUDE_ENV_FILE: envFile });
    expect(result.status).toBe(0);
    expect(bootstrapContext(result.stdout)).toContain("<EXTREMELY_IMPORTANT>");
    expect(result.stderr).toContain(envFile);
    expect(existsSync(envFile)).toBe(false);
  });

  // bad_the_old_name_is_gone — ADR 0007 decision 4 is a HARD rename, read
  // strictly by the owner: no alias AND no tombstone. The plugin ships nothing
  // under the old name, so a session that types it gets the shell's own
  // `command not found`. This test is what stops an alias being reinstated.
  test("the plugin ships no entry point under the old name", () => {
    expect(existsSync(join(repoRoot, "bin/uc"))).toBe(false);
    // Nothing else in bin/ answers to it either.
    expect(readdirSync(join(repoRoot, "bin"))).not.toContain("uc");
  });

  test("the old name resolves to nothing on PATH after the hook exports bin/", () => {
    const envFile = join(scratch(), "env.sh");
    expect(runHook({ CLAUDE_ENV_FILE: envFile }).status).toBe(0);
    // PATH is pinned to a bare base BEFORE sourcing, so the lookup answers for
    // the plugin's own bin/ and not for whatever the developer has installed.
    // (A machine with an older plugin cache really does still have a `uc`.)
    const look = (name: string) =>
      spawnSync("bash", ["-c", `export PATH=/usr/bin:/bin; source "${envFile}"; command -v ${name}`], {
        encoding: "utf8",
        env: { ...process.env, PATH: "/usr/bin:/bin" }
      });
    // `command -v` is the lookup itself: non-zero means no such command.
    const probe = look("uc");
    expect(probe.status).not.toBe(0);
    expect(probe.stdout.trim()).toBe("");
    // ...while the new name does resolve, from that same PATH.
    const ok = look("use-cases");
    expect(ok.status, ok.stderr).toBe(0);
    expect(ok.stdout).toContain(`${repoRoot}/bin/use-cases`);
  });
});
