// Currency guard: the AGENT-facing material (the shipped skill + the MCP
// playbooks) must track the 0.1.0 feature surface. Agents are half the users; if
// a command ships without its agent guidance, CI should go red HERE rather than
// letting the skill silently drift back to being showcase-centric.
//
// The 0.1.0 headline is the KEYLESS DAILY LOOP: bind -> verify -> scan shows
// VERIFIED_LOCAL, with NO keys and NO CI. Signing (keygen + prove / recover
// --signing-key-env) is the OPT-IN upgrade to FRESH for release/audit. `recover`
// is the one-command path back to green.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { getMcpPrompt, mcpPrompts } from "../../../packages/mcp/src/prompts.js";

const repoRoot = resolve(import.meta.dirname, "../../..");
const skillPath = resolve(repoRoot, ".agents/skills/use-case-matrix/SKILL.md");
const skill = readFileSync(skillPath, "utf8");

function promptText(name: string, args: Record<string, string> = {}): string {
  const outcome = getMcpPrompt(name, args);
  if (!outcome.ok) {
    throw new Error(`prompt ${name} did not build: ${outcome.message}`);
  }
  return outcome.result.messages.map((message) => message.content.text).join("\n");
}

describe("agent enablement currency", () => {
  describe("shipped SKILL.md teaches the keyless daily loop", () => {
    test("names the keyless daily loop and its keyless green signal", () => {
      expect(skill.toLowerCase()).toContain("keyless");
      expect(skill).toContain("VERIFIED_LOCAL");
    });

    test("teaches the bind -> verify -> scan core loop commands", () => {
      expect(skill).toContain("ucm bind");
      expect(skill).toContain("ucm verify");
      expect(skill).toContain("ucm scan");
    });

    test("teaches recover as the one-command path back to green", () => {
      expect(skill).toContain("ucm recover");
    });

    test("frames signing (keygen / prove) as the OPT-IN release upgrade, not the daily default", () => {
      expect(skill).toContain("FRESH");
      // keygen is named as the opt-in signed-tier setup.
      expect(skill).toContain("ucm keygen");
    });
  });

  describe("MCP playbooks expose the new commands", () => {
    test("a recover playbook is registered and references ucm recover", () => {
      const names = mcpPrompts.map((prompt) => prompt.name);
      expect(names).toContain("ucm/recover-suspect-row");
      const text = promptText("ucm/recover-suspect-row", { row: "auth.login" });
      expect(text).toContain("ucm recover");
    });

    test("the recover playbook drives to VERIFIED_LOCAL keyless-first (signing = opt-in)", () => {
      const text = promptText("ucm/recover-suspect-row", { row: "auth.login" });
      expect(text).toContain("VERIFIED_LOCAL");
      // The signed upgrade is the opt-in path, not the default.
      expect(text).toContain("--signing-key-env");
    });

    test("adopt-repo teaches the keyless loop before the signed CI tier", () => {
      const text = promptText("ucm/adopt-repo", { repo: "/repo" });
      expect(text).toContain("ucm verify");
      expect(text).toContain("VERIFIED_LOCAL");
      const verifyAt = text.indexOf("VERIFIED_LOCAL");
      const proveAt = text.indexOf("ucm prove");
      // The keyless green is introduced before the CI-only prove step.
      expect(verifyAt).toBeGreaterThanOrEqual(0);
      expect(proveAt).toBeGreaterThan(verifyAt);
    });

    test("bind-row uses the real explicit-mode span flags (--start-line/--end-line)", () => {
      const text = promptText("ucm/bind-row", { row: "auth.login", file: "src/x.ts" });
      expect(text).toContain("ucm bind");
      expect(text).toContain("--start-line");
      expect(text).toContain("--end-line");
      // The stale single-line flag must not creep back in for explicit mode.
      expect(text).not.toMatch(/--mode explicit[^\n]*--line /);
    });
  });
});
