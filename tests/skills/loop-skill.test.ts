import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { CANONICAL_SKILLS } from "../../packages/core/src/skills/canonicalSkills.js";

const repoRoot = resolve(import.meta.dirname, "../..");
const skillPath = join(repoRoot, "skills/use-case-driven-development/SKILL.md");
const body = () => readFileSync(skillPath, "utf8");

//: @use-case:plugin.init.loop_skill_ported
describe("the use-case-driven-development skill ships in the plugin, host-neutral", () => {
  test("it exists, is named for its directory, and is canonical", () => {
    expect(existsSync(skillPath)).toBe(true);
    expect(body()).toMatch(/^name: use-case-driven-development$/m);
    expect(CANONICAL_SKILLS).toContain("use-case-driven-development");
  });

  test("it carries nothing that only one machine or host can do", () => {
    const text = body();
    for (const forbidden of ["talk-to-myself", "npm install", "~/.claude", "swift-use-case-driven-development", "simulator", "Xcode", "xcode", "agent-setup", "/merge"]) {
      expect(text, forbidden).not.toContain(forbidden);
    }
  });

  test("it reads AGENTS.md first, sends a bare repo to init, and covers the whole loop", () => {
    const text = body();
    expect(text).toContain("## Use-case driven development");
    expect(text).toContain("AGENTS.md");
    expect(text).toContain("/use-cases:init");
    for (const phase of ["UNDERSTAND", "FRAME", "BUILD", "VERIFY", "SIGN-OFF", "LAND"]) {
      expect(text, phase).toContain(phase);
    }
    for (const cmd of ["uc bind", "uc verify", "uc scan", "uc recover", "use_case_upsert", "matrix_validate", "showcase_start", "uc scan --repo . --gate"]) {
      expect(text, cmd).toContain(cmd);
    }
    expect(text).toContain("VERIFIED_LOCAL");
  });
});
//: @use-case:end plugin.init.loop_skill_ported
