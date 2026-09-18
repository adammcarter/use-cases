// The black-box oracle for plugin.init.loop_skill_ported.
//
// The row is about a SHIPPED ARTEFACT — the loop skill every host reads — so
// this inspects what ships and drives the CLI for the command surface. No
// product imports.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { runUc, runUcJson } from "../helpers/uc-binary";

const repoRoot = resolve(import.meta.dirname, "../..");
const SKILL = "use-case-driven-development";

function skillBody(): string {
  return readFileSync(join(repoRoot, "skills", SKILL, "SKILL.md"), "utf8");
}

function frontmatter(source: string): Record<string, string> {
  const match = /^---\n([\s\S]*?)\n---\n/.exec(source);
  expect(match, "a skill must open with YAML frontmatter").not.toBeNull();
  const fields: Record<string, string> = {};
  for (const line of match![1].split("\n")) {
    const pair = /^([a-z_]+):\s*(.*)$/.exec(line);
    if (pair) fields[pair[1]] = pair[2].replace(/^["']|["']$/g, "");
  }
  return fields;
}

//: @use-case:plugin.init.loop_skill_ported#blackbox
describe("plugin.init.loop_skill_ported", () => {
  // golden_present_and_canonical. Named for its directory, and in the set the
  // doctor validates — otherwise no host sees it.
  test("the skill is named for its directory and doctor counts it as canonical", () => {
    expect(readdirSync(join(repoRoot, "skills"))).toContain(SKILL);
    expect(frontmatter(skillBody()).name).toBe(SKILL);

    const { envelope } = runUcJson<{ skill_count: number }>(["doctor", "skills", "--repo", "."], {
      cwd: repoRoot
    });
    expect(envelope.ok, "the shipped skill set must be healthy").toBe(true);
    expect(envelope.data.skill_count).toBeGreaterThanOrEqual(5);
  });

  // bad_nothing_host_specific. These bodies ship to every host, so anything
  // only one machine can do makes the skill wrong everywhere else.
  test("it carries nothing that only one machine or host can do", () => {
    const body = skillBody();
    for (const forbidden of [/talk-to-myself/, /npm install/, /~\/\.claude/, /agent-setup/, /simulator/i, /xcode/i]) {
      expect(body, `the loop skill must not mention ${forbidden}`).not.toMatch(forbidden);
    }
  });

  // golden_covers_the_loop. The phases, the entry point, and the commands each
  // phase names — a skill that skipped one would send an agent somewhere else.
  test("it reads AGENTS.md first, routes a bare repo to init, and covers the whole loop", () => {
    const body = skillBody();

    expect(body).toContain("AGENTS.md");
    expect(body, "a repo with no decision goes to init").toContain("/use-cases:init");
    for (const phase of ["UNDERSTAND", "FRAME", "BUILD", "VERIFY", "SIGN-OFF", "LAND"]) {
      expect(body, `the loop must cover ${phase}`).toContain(phase);
    }
    for (const command of ["bind", "verify", "scan", "recover"]) {
      expect(body, `the loop must name use-cases ${command}`).toMatch(new RegExp(`\\b${command}\\b`));
    }
  });

  // Every use-cases command the skill cites must be one the CLI actually ships — the
  // same guarantee the agent bodies are held to.
  test("every use-cases command the skill cites is one the CLI ships", () => {
    const help = runUc(["--help"]);
    expect(help.status).toBe(0);
    const dispatchable = new Set(
      help.stdout
        .split("\n")
        .map((line) => /^ {2}([a-z][a-z-]+(?: [a-z][a-z-]+)?)\s{2,}/.exec(line)?.[1])
        .filter((value): value is string => Boolean(value))
    );

    for (const match of skillBody().matchAll(/`use-cases\s+([^`]+?)`/g)) {
      const tokens = match[1].trim().split(/\s+/);
      const [first, second] = tokens;
      const cited = second && !second.startsWith("-") ? `${first} ${second}` : first;
      expect(
        dispatchable.has(cited) || dispatchable.has(first),
        `the skill cites \`use-cases ${cited}\`, which the CLI does not ship`
      ).toBe(true);
    }
  });
});
//: @use-case:end plugin.init.loop_skill_ported#blackbox
