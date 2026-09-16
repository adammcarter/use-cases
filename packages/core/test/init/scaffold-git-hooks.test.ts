import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { scaffoldWorkspace } from "../../src/init/scaffold.js";

function git(repoRoot: string, args: string[]): string {
  const result = spawnSync("git", args, { cwd: repoRoot, encoding: "utf8" });
  return result.stdout.trim();
}

function runHook(repoRoot: string, hook: string, env: Record<string, string> = {}) {
  return spawnSync("bash", [join(repoRoot, hook)], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, PATH: "/usr/bin:/bin", ...env }
  });
}

//: @use-case:plugin.init.wires_git_hooks
describe("uc init wires the pre-commit and pre-push hooks", () => {
  let repoRoot: string;
  beforeEach(() => {
    repoRoot = mkdtempSync(join(tmpdir(), "ucm-init-hooks-"));
    spawnSync("git", ["init", "-q", "."], { cwd: repoRoot });
  });
  afterEach(() => { rmSync(repoRoot, { recursive: true, force: true }); });

  test("a fresh git repo gets both hooks, executable, and core.hooksPath set", () => {
    const result = scaffoldWorkspace({ repoRoot });
    expect(result.status).toBe("created");
    for (const hook of [".githooks/pre-commit", ".githooks/pre-push"]) {
      expect(existsSync(join(repoRoot, hook)), hook).toBe(true);
      expect(statSync(join(repoRoot, hook)).mode & 0o111).not.toBe(0);
      expect(result.created_files).toContain(hook);
    }
    expect(git(repoRoot, ["config", "core.hooksPath"])).toBe(".githooks");
    const preCommit = readFileSync(join(repoRoot, ".githooks/pre-commit"), "utf8");
    expect(preCommit).toContain("matrix validate");
    expect(preCommit).toContain("validate-ledger");
    expect(preCommit).toContain("INVALID");
    const prePush = readFileSync(join(repoRoot, ".githooks/pre-push"), "utf8");
    expect(prePush).toContain("impact");
    expect(prePush).toContain("scan");
    expect(prePush.trim().endsWith("exit 0")).toBe(true);
    expect(result.git_hooks).toEqual({ hooks_dir: ".githooks", hooks_path_set: true, extended: [] });
  });

  test("an existing hooksPath is kept and its pre-commit is extended, not replaced", () => {
    mkdirSync(join(repoRoot, "hooks"));
    const theirs = "#!/usr/bin/env bash\necho theirs-ran\n";
    writeFileSync(join(repoRoot, "hooks/pre-commit"), theirs);
    chmodSync(join(repoRoot, "hooks/pre-commit"), 0o755);
    spawnSync("git", ["config", "core.hooksPath", "hooks"], { cwd: repoRoot });
    const result = scaffoldWorkspace({ repoRoot });
    expect(git(repoRoot, ["config", "core.hooksPath"])).toBe("hooks");
    const preCommit = readFileSync(join(repoRoot, "hooks/pre-commit"), "utf8");
    expect(preCommit.startsWith(theirs)).toBe(true);
    expect(preCommit).toContain("matrix validate");
    expect(existsSync(join(repoRoot, "hooks/pre-push"))).toBe(true);
    expect(existsSync(join(repoRoot, ".githooks"))).toBe(false);
    expect(result.git_hooks).toEqual({ hooks_dir: "hooks", hooks_path_set: false, extended: ["hooks/pre-commit"] });
    // Running theirs still runs first.
    const run = runHook(repoRoot, "hooks/pre-commit");
    expect(run.stdout).toContain("theirs-ran");
  });

  test("with no uc on PATH the pre-commit warns and exits 0 instead of locking the repo", () => {
    scaffoldWorkspace({ repoRoot });
    const run = runHook(repoRoot, ".githooks/pre-commit");
    expect(run.status).toBe(0);
    expect(run.stderr).toMatch(/uc .*not found/i);
    expect(run.stderr).toContain("install");
  });

  test("a directory that is not a git repo still gets the hook files and says hooksPath was not set", () => {
    const plain = mkdtempSync(join(tmpdir(), "ucm-init-nogit-"));
    try {
      const result = scaffoldWorkspace({ repoRoot: plain });
      expect(result.status).toBe("created");
      expect(existsSync(join(plain, ".githooks/pre-commit"))).toBe(true);
      expect(result.git_hooks).toEqual({ hooks_dir: ".githooks", hooks_path_set: false, extended: [] });
      expect(result.next_steps.join("\n")).toContain("core.hooksPath");
    } finally {
      rmSync(plain, { recursive: true, force: true });
    }
  });
});
//: @use-case:end plugin.init.wires_git_hooks
