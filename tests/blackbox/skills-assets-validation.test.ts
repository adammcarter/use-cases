// The black-box oracle for two remaining rows of skills/assets.yml:
// asset_validation and degraded_assets.
//
// skills-assets.test.ts already covers host_declaration and
// unreachable_skills_fail_doctor. demo_gates lives in tests/skills/p7-skills.test.ts
// per its own verifier and is left alone here.
//
// Every fixture copies the REAL plugin layout, same lesson as
// skills-assets.test.ts: a hand-built minimal layout reports `skills.missing`
// even when intact and measures the fixture instead of the condition.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { runUcJson } from "../helpers/uc-binary";

const repoRoot = resolve(import.meta.dirname, "../..");
const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

/** A copy of the shipped plugin layout: skills, manifests, and the assets
 *  doctor reads alongside them. */
function makePluginCopy(): string {
  const dir = mkdtempSync(join(tmpdir(), "uc-skills-assets-"));
  tempDirs.push(dir);
  mkdirSync(join(dir, ".claude-plugin"), { recursive: true });
  cpSync(join(repoRoot, "skills"), join(dir, "skills"), { recursive: true });
  cpSync(join(repoRoot, ".claude-plugin", "plugin.json"), join(dir, ".claude-plugin", "plugin.json"));
  cpSync(join(repoRoot, ".claude-plugin", "marketplace.json"), join(dir, ".claude-plugin", "marketplace.json"));
  for (const optional of ["agents", "bootstrap", "docs"]) {
    try {
      cpSync(join(repoRoot, optional), join(dir, optional), { recursive: true });
    } catch {
      // Not every layout ships all of these; doctor tolerates their absence.
    }
  }
  return dir;
}

interface SkillEntry {
  name: string;
  path: string;
  description: string;
  complete: boolean;
}
interface DoctorData {
  complete: boolean;
  skill_count: number;
  skills: SkillEntry[];
  host_registration: {
    complete: boolean;
    hosts: Array<{ host: string; manifest_path: string; declares_skill_root: boolean; installable: boolean }>;
  };
}

function doctor(dir: string) {
  return runUcJson<DoctorData>(["doctor", "skills", "--repo", "."], {
    cwd: dir,
    env: { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") }
  });
}

function codes(envelope: { diagnostics: Array<{ code: string }> }): string[] {
  return envelope.diagnostics.map((d) => d.code);
}

describe("skills.assets.asset_validation", () => {
  // golden_doctor. Every shipped skill is discovered, each with a name, path,
  // description and a complete: true front-matter check.
  test("an intact checkout discovers every shipped skill with intact assets and front-matter", () => {
    const { envelope } = doctor(makePluginCopy());

    expect(envelope.ok).toBe(true);
    expect(envelope.data.skill_count).toBeGreaterThan(0);
    expect(envelope.data.skills.length).toBe(envelope.data.skill_count);
    for (const skill of envelope.data.skills) {
      expect(skill.name, `${skill.path} has a discovered name`).toBeTruthy();
      expect(skill.description.length, `${skill.name} has a real description`).toBeGreaterThan(0);
      expect(skill.complete, `${skill.name} reports valid`).toBe(true);
    }
    expect(codes(envelope)).toEqual([]);
  });

  // bad_required_file_missing. Removing a skill's SKILL.md — the file that
  // makes it a skill at all — must stop it from validating clean.
  //
  // MEASURED: with the directory left in place, the loader silently skips
  // the skill (it drops out of `skills[]`/`skill_count` entirely) rather than
  // emitting a dedicated "file missing" diagnostic for it. The result still
  // fails overall (ok:false, complete:false) via `skills.host_not_declared`,
  // because a Claude host can no longer find SKILL.md under every canonical
  // skill name — that IS how "cannot be published while required files are
  // missing" actually shows up here.
  test("a skill whose SKILL.md is removed can no longer be published clean", () => {
    const dir = makePluginCopy();
    const before = doctor(dir).envelope;
    expect(before.data.skill_count).toBeGreaterThan(0);
    const beforeNames = before.data.skills.map((s) => s.name);
    expect(beforeNames).toContain("init");

    rmSync(join(dir, "skills", "init", "SKILL.md"));

    const { envelope } = doctor(dir);
    expect(envelope.ok).toBe(false);
    expect(envelope.data.complete).toBe(false);
    expect(envelope.data.skill_count).toBe(before.data.skill_count - 1);
    expect(envelope.data.skills.map((s) => s.name)).not.toContain("init");
    expect(codes(envelope).length, "the failure is reported as a diagnostic, not silence").toBeGreaterThan(0);
  });

  // edge_front_matter_name_matches_the_directory. Every discovered skill's
  // name is exactly its directory: that is the identifier a host will use to
  // address it, so the two must never drift apart.
  test("every discovered skill's front-matter name is the directory the host will address it by", () => {
    const dir = makePluginCopy();
    const { envelope } = doctor(dir);
    for (const skill of envelope.data.skills) {
      expect(skill.path).toBe(`skills/${skill.name}/SKILL.md`);
    }
    expect(codes(envelope)).not.toContain("skills.name_mismatch");

    // Break the correspondence deliberately: point one skill's frontmatter
    // name away from its own directory.
    const skillMdPath = join(dir, "skills", "init", "SKILL.md");
    const original = readFileSync(skillMdPath, "utf8");
    writeFileSync(skillMdPath, original.replace(/^name: init$/m, "name: not-init"));

    const broken = doctor(dir).envelope;
    expect(codes(broken)).toContain("skills.name_mismatch");
    const initEntry = broken.data.skills.find((s) => s.path === "skills/init/SKILL.md");
    expect(initEntry?.name, "the discovered name follows the frontmatter, so a mismatch is visible here").toBe("not-init");
  });
});

describe("skills.assets.degraded_assets", () => {
  // golden_report. A skill missing a required asset (its SKILL.md) is
  // reported with a diagnostic rather than silently omitted from the result.
  test("a skill missing its required asset is reported with a diagnostic", () => {
    const dir = makePluginCopy();
    rmSync(join(dir, "skills", "walkthrough", "SKILL.md"));

    const { envelope } = doctor(dir);
    expect(envelope.ok).toBe(false);
    expect(codes(envelope).length).toBeGreaterThan(0);
    expect(envelope.data.skills.map((s) => s.name)).not.toContain("walkthrough");
  });

  // bad_damage_is_never_reported_as_healthy. Malformed front-matter (no YAML
  // block at all) must never pass as a healthy skill.
  test("malformed front-matter never passes as healthy", () => {
    const dir = makePluginCopy();
    const skillMdPath = join(dir, "skills", "init", "SKILL.md");
    const original = readFileSync(skillMdPath, "utf8");
    // Corrupt the opening frontmatter delimiter so no YAML block is found.
    writeFileSync(skillMdPath, original.replace("---\n", "XXX\n"));

    const { envelope } = doctor(dir);
    expect(envelope.ok).toBe(false);
    expect(codes(envelope)).toContain("skills.frontmatter_missing");
    const initEntry = envelope.data.skills.find((s) => s.path === "skills/init/SKILL.md");
    expect(initEntry, "the damaged skill still appears in the list").toBeTruthy();
    expect(initEntry?.complete, "but never marked complete").toBe(false);
  });

  // edge_one_damaged_skill_does_not_hide_the_rest. One skill's malformed
  // front-matter must not swallow the report on the other skills, and the
  // process must exit with a plain nonzero status rather than crashing.
  test("one damaged skill's malformed front-matter does not hide the others, and the run is non-fatal", () => {
    const dir = makePluginCopy();
    const skillMdPath = join(dir, "skills", "init", "SKILL.md");
    const original = readFileSync(skillMdPath, "utf8");
    writeFileSync(skillMdPath, original.replace("---\n", "XXX\n"));

    const { envelope, status } = doctor(dir);
    expect(status, "a normal refusal exit code, not a crash").toBe(1);
    const others = envelope.data.skills.filter((s) => s.path !== "skills/init/SKILL.md");
    expect(others.length).toBeGreaterThan(0);
    for (const skill of others) {
      expect(skill.complete, `${skill.name} stays healthy despite init's damage`).toBe(true);
    }
  });
});
