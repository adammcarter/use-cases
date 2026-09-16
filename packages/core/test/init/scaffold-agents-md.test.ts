import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { scaffoldWorkspace } from "../../src/init/scaffold.js";

const SECTION = "## Use-case driven development";
const today = new Date().toISOString().slice(0, 10);

function agentsMd(repoRoot: string): string {
  return readFileSync(join(repoRoot, "AGENTS.md"), "utf8");
}

//: @use-case:plugin.init.records_decision_in_agents_md
describe("uc init records the use-case-driven decision in AGENTS.md", () => {
  let repoRoot: string;
  beforeEach(() => { repoRoot = mkdtempSync(join(tmpdir(), "ucm-init-agents-")); });
  afterEach(() => { rmSync(repoRoot, { recursive: true, force: true }); });

  test("creates AGENTS.md with the section, today's date, the skill signpost and the instruction", () => {
    const result = scaffoldWorkspace({ repoRoot });
    expect(result.status).toBe("created");
    expect(result.created_files).toContain("AGENTS.md");
    const body = agentsMd(repoRoot);
    expect(body).toContain(`${SECTION}\n\nyes — ${today}`);
    expect(body).toContain("use-case-driven-development");
    expect(body).toContain("use-cases");
    expect(body).toMatch(/follow/i);
    expect(result.agents_md).toEqual({ status: "created", decision: "yes" });
  });

  test("appends the section after existing content without touching it", () => {
    const existing = "# my-app\n\nSome rules that were here first.\n";
    writeFileSync(join(repoRoot, "AGENTS.md"), existing);
    const result = scaffoldWorkspace({ repoRoot });
    const body = agentsMd(repoRoot);
    expect(body.startsWith(existing)).toBe(true);
    expect(body.indexOf(SECTION)).toBeGreaterThan(existing.length - 1);
    expect(result.agents_md).toEqual({ status: "appended", decision: "yes" });
  });

  test("leaves an existing section alone and reports its answer", () => {
    const existing = `# my-app\n\n${SECTION}\n\nno — 2026-01-02\n`;
    writeFileSync(join(repoRoot, "AGENTS.md"), existing);
    const result = scaffoldWorkspace({ repoRoot });
    expect(agentsMd(repoRoot)).toBe(existing);
    expect(result.agents_md).toEqual({ status: "already_recorded", decision: "no" });
    expect(result.created_files).not.toContain("AGENTS.md");
  });

  test("a second run is blocked and AGENTS.md still has exactly one section", () => {
    expect(scaffoldWorkspace({ repoRoot }).status).toBe("created");
    const second = scaffoldWorkspace({ repoRoot });
    expect(second.status).toBe("blocked");
    expect(agentsMd(repoRoot).split(SECTION).length - 1).toBe(1);
    expect(existsSync(join(repoRoot, "AGENTS.md"))).toBe(true);
  });
});
//: @use-case:end plugin.init.records_decision_in_agents_md
