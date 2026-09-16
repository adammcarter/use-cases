// The black-box oracle for the two white-box rows of skills/assets.yml, plus
// the host-registration row that already had a black-box verifier.
//
// Every fixture copies the REAL plugin layout. An earlier attempt built a
// minimal one by hand and reported `skills.missing` even when intact, so every
// case measured the fixture rather than the condition under test.
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
  const dir = mkdtempSync(join(tmpdir(), "uc-skills-"));
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

interface DoctorData {
  complete: boolean;
  skill_count: number;
  host_registration: {
    complete: boolean;
    hosts: Array<{ host: string; manifest_path: string; declares_skill_root: boolean; installable: boolean }>;
  };
}

function doctor(dir: string) {
  return runUcJson<DoctorData>(["doctor", "skills", "--repo", "."], { cwd: dir, env: {} });
}

function codes(envelope: { diagnostics: Array<{ code: string }> }): string[] {
  return envelope.diagnostics.map((d) => d.code);
}

//: @use-case:skills.assets.host_declaration#blackbox
describe("skills.assets.host_declaration", () => {
  // golden_manifests. Skills sit where the host scans, and the marketplace
  // manifest is what makes the plugin manifest get read at all.
  test("an intact layout reports every skill reachable by the host", () => {
    const { envelope } = doctor(makePluginCopy());

    expect(envelope.ok).toBe(true);
    expect(envelope.data.skill_count).toBeGreaterThan(0);
    expect(envelope.data.host_registration.complete).toBe(true);
    const claude = envelope.data.host_registration.hosts.find((h) => h.host === "claude");
    expect(claude?.declares_skill_root).toBe(true);
    expect(claude?.installable).toBe(true);
    expect(codes(envelope)).toEqual([]);
  });

  // bad_moved_skills. A skill outside the scanned directory is unreachable, and
  // that is an error rather than a smaller pass.
  test("a canonical skill moved out of skills/ is unreachable, not a pass", () => {
    const dir = makePluginCopy();
    mkdirSync(join(dir, "elsewhere"), { recursive: true });
    cpSync(join(dir, "skills", "use-cases"), join(dir, "elsewhere", "use-cases"), { recursive: true });
    rmSync(join(dir, "skills", "use-cases"), { recursive: true, force: true });

    const { envelope } = doctor(dir);
    expect(envelope.ok).toBe(false);
    expect(codes(envelope)).toContain("skills.host_not_declared");
    expect(codes(envelope)).toContain("skills.missing");
    expect(envelope.data.host_registration.hosts[0].declares_skill_root).toBe(false);
  });

  // edge_marketplace_manifest_is_what_makes_it_readable. Declared but not
  // installable is still unreachable — the two are separate conditions with
  // separate codes.
  test("without a marketplace manifest the plugin is declared but not installable", () => {
    const dir = makePluginCopy();
    rmSync(join(dir, ".claude-plugin", "marketplace.json"));

    const { envelope } = doctor(dir);
    expect(envelope.ok).toBe(false);
    expect(codes(envelope)).toContain("skills.host_not_installable");
    const claude = envelope.data.host_registration.hosts[0];
    expect(claude.declares_skill_root, "the skills are still where the host scans").toBe(true);
    expect(claude.installable, "but nothing can install them").toBe(false);
  });
});
//: @use-case:end skills.assets.host_declaration#blackbox

//: @use-case:skills.assets.unreachable_skills_fail_doctor#blackbox
describe("skills.assets.unreachable_skills_fail_doctor", () => {
  // golden_intact_checkout.
  test("an intact checkout reports the skills as registered", () => {
    const { envelope } = doctor(makePluginCopy());
    expect(envelope.ok).toBe(true);
    expect(envelope.data.host_registration.complete).toBe(true);
    const claude = envelope.data.host_registration.hosts[0];
    expect(claude.host).toBe("claude");
    expect(claude.manifest_path).toContain("plugin.json");
  });

  // bad_undeclared. Skills that exist on disk but no host can load are an
  // error, and the result is explicitly not complete.
  test("skills no host can load are an error, and the result is not complete", () => {
    const dir = makePluginCopy();
    rmSync(join(dir, "skills", "use-cases"), { recursive: true, force: true });

    const { envelope } = doctor(dir);
    expect(envelope.ok).toBe(false);
    expect(envelope.data.complete).toBe(false);
    expect(codes(envelope)).toContain("skills.host_not_declared");
  });

  // bad_uninstallable.
  test("a declared skill root is still unreachable without a marketplace manifest", () => {
    const dir = makePluginCopy();
    rmSync(join(dir, ".claude-plugin", "marketplace.json"));
    expect(codes(doctor(dir).envelope)).toContain("skills.host_not_installable");
  });

  // edge_manifest_missing. Distinct from a manifest that is present but wrong:
  // with none at all, no host is reported.
  test("with no plugin manifest at all, no host is reported and the code differs", () => {
    const dir = makePluginCopy();
    rmSync(join(dir, ".claude-plugin", "plugin.json"));

    const { envelope } = doctor(dir);
    expect(envelope.ok).toBe(false);
    expect(codes(envelope)).toContain("skills.host_manifest_missing");
    expect(envelope.data.host_registration.hosts, "no manifest means no host").toEqual([]);
    expect(envelope.data.host_registration.complete).toBe(false);
  });

  // bad_misdirected is NOT asserted here, and the gap is deliberate.
  //
  // The row claims "a manifest that declares a directory not actually holding
  // the canonical skills does not count as declared". Measured against the real
  // layout, pointing the manifest's `skills` key at a directory that does not
  // exist still reports ok:true, declares_skill_root:true and zero diagnostics —
  // skills are discovered by CONVENTION (skills/<name>/SKILL.md at the plugin
  // root), so the key is not what makes them reachable.
  //
  // So the row asserts behaviour the tool does not have. Writing a test that
  // passes would paper over that; changing the row is a behaviour decision and
  // belongs to the owner. Flagged here until they make it.
  test.todo("bad_misdirected — the row claims a behaviour the tool does not have; see the note above");
});
//: @use-case:end skills.assets.unreachable_skills_fail_doctor#blackbox
