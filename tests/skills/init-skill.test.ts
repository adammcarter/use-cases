import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const skillPath = join(repoRoot, "skills/init/SKILL.md");

//: @use-case:plugin.init.skill_hands_off
describe("the init skill runs use-cases init and hands over to the loop", () => {
  test("the skill runs use-cases init, reads AGENTS.md back, and ends by invoking the loop skill", () => {
    expect(existsSync(skillPath)).toBe(true);
    const body = readFileSync(skillPath, "utf8");
    expect(body).toMatch(/^name: init$/m);
    expect(body).toContain("use-cases init --repo .");
    expect(body).toContain("AGENTS.md");
    const lastParagraph = body.trim().split(/\n\s*\n/).pop() ?? "";
    expect(lastParagraph).toContain("use-case-driven-development");
  });

  test("an already-initialised repo skips straight to the loop", () => {
    const body = readFileSync(skillPath, "utf8");
    expect(body).toMatch(/already exists|blocked/i);
    expect(body).toMatch(/recorded answer|read the answer|AGENTS\.md/);
  });
});
//: @use-case:end plugin.init.skill_hands_off
