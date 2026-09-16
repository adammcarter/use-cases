import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";

// The plugin ships a trusted session-start bootstrap and per-host delivery so an
// installed agent receives bootstrap/use-cases.md at session start without
// having to discover it by reading the repo. See critical-info-bootstrap.
const repoRoot = resolve(import.meta.dirname, "../../..");
const hookScript = resolve(repoRoot, "hooks/session-start");
const BOOTSTRAP_MARKER = "Use Cases Activation";

function runHook(env: Record<string, string>) {
  return spawnSync("bash", [hookScript], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { PATH: process.env.PATH ?? "", ...env }
  });
}

describe("session-start bootstrap delivery", () => {
  test("the polyglot hook script is shipped and executable", () => {
    expect(existsSync(hookScript)).toBe(true);
    // Keep the executable bit for direct/manual use; host commands also invoke
    // through bash so packed install paths do not depend on tar mode preservation.
    expect(statSync(hookScript).mode & 0o111).not.toBe(0);
  });

  test("Claude Code shape: hookSpecificOutput.additionalContext carries the bootstrap", () => {
    const result = runHook({ CLAUDE_PLUGIN_ROOT: repoRoot });
    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload.hookSpecificOutput.hookEventName).toBe("SessionStart");
    expect(payload.hookSpecificOutput.additionalContext).toContain(BOOTSTRAP_MARKER);
    expect(payload.additional_context).toBeUndefined();
    expect(payload.additionalContext).toBeUndefined();
  });

  test("Copilot shape: top-level additionalContext carries the bootstrap", () => {
    const result = runHook({ CLAUDE_PLUGIN_ROOT: repoRoot, COPILOT_CLI: "1" });
    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload.additionalContext).toContain(BOOTSTRAP_MARKER);
    expect(payload.hookSpecificOutput).toBeUndefined();
  });

  test("Codex shape (no Copilot env): hookSpecificOutput.additionalContext", () => {
    const result = runHook({ PLUGIN_ROOT: repoRoot });
    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout);
    expect(payload.hookSpecificOutput.additionalContext).toContain(BOOTSTRAP_MARKER);
  });

  test("emitted bootstrap is the trusted EXTREMELY_IMPORTANT block, not arbitrary text", () => {
    const result = runHook({ CLAUDE_PLUGIN_ROOT: repoRoot });
    const ctx = JSON.parse(result.stdout).hookSpecificOutput.additionalContext as string;
    expect(ctx).toContain("<EXTREMELY_IMPORTANT>");
    const bootstrap = readFileSync(resolve(repoRoot, "bootstrap/use-cases.md"), "utf8");
    // The full bootstrap tail must survive (no truncation).
    expect(ctx).toContain(bootstrap.trim().slice(-40));
  });

  test("Claude hooks.json declares SessionStart wired to the script", () => {
    for (const [file, matcherIncludes] of [
      ["hooks/hooks.json", "startup"]
    ] as const) {
      const manifest = JSON.parse(readFileSync(resolve(repoRoot, file), "utf8"));
      const sessionStart = manifest.hooks.SessionStart;
      expect(Array.isArray(sessionStart)).toBe(true);
      expect(sessionStart[0].matcher).toContain(matcherIncludes);
      expect(JSON.stringify(sessionStart[0].hooks)).toContain("session-start");
      expect(JSON.stringify(sessionStart[0].hooks)).toContain("bash");
    }
  });


});
