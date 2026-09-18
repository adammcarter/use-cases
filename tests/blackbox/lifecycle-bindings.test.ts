// The black-box oracle for lifecycle/bindings.yml.
//
// Deliberately self-contained rather than sharing the signals fixtures. Every
// row declares its oracle file as a verifier input, so a shared file means one
// edit stales every row bound to it — measured on the signals file, where
// renaming five tests dropped all twelve rows to STALE_LOCAL at once. One file
// per feature area keeps that blast radius to the area being worked on.
//
// Everything here talks only to the binary. Each test builds its workspace from
// scratch and points UC_RUN_KEY_FILE at a throwaway path, so no test reads or
// writes the developer's own machine key.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { runUcJson } from "../helpers/uc-binary";

const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

const WORKSPACE_CONFIG = `schema_version: 1
workspace_id: probe
component_id: probe
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
`;

function rowYaml(name: string): string {
  return `  - id: probe.core.${name}
    title: Row ${name}
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Probe ${name}.
    preconditions: [A source file exists.]
    trigger: An agent verifies.
    scenarios:
      - id: probe.core.${name}.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [It passes.]
    observable_outcomes: [The row reaches VERIFIED_LOCAL.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        script:
          kind: script
          evidence_kind: test_result
          command: ["/bin/sh", "-c", "exit 0"]
          inputs: ["src/${name}.ts"]
      requirements:
        - evidence_kind: test_result
          required_verifiers: [script]
          minimum_count: 1
    approval_policy:
      mode: none
`;
}

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

/**
 * A workspace with the named rows, nothing bound yet. Each source file holds
 * three well-separated declarations so two suffixed spans both fit — a span
 * past end-of-file fails with BIND_SPAN_OUT_OF_RANGE rather than doing anything
 * interesting.
 */
function makeWorkspace(rows: string[]): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-bindings-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  mkdirSync(join(dir, "src"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(
    join(dir, "use-cases", "probe.yml"),
    `schema_version: 1\nfeature:\n  id: probe.core\n  name: Probe\n  summary: Probe.\nuse_cases:\n${rows.map(rowYaml).join("")}`
  );
  for (const name of rows) {
    writeFileSync(
      join(dir, "src", `${name}.ts`),
      `export function ${name}One() {\n  return 1;\n}\n\nexport function ${name}Two() {\n  return 2;\n}\n\nexport function ${name}Three() {\n  return 3;\n}\n`
    );
  }
  return { dir, env };
}

/** Run a use-cases subcommand against this workspace, with --repo wired in. */
function uc(workspace: Workspace, args: string[]) {
  const [command, ...rest] = args;
  return runUcJson([command, "--repo", ".", ...rest], { cwd: workspace.dir, env: workspace.env });
}

function bind(workspace: Workspace, row: string, file: string, start: number, end: number, suffix?: string) {
  return uc(workspace, [
    "bind", "--row", `probe.core.${row}`, "--file", file,
    "--mode", "explicit", "--start-line", String(start), "--end-line", String(end),
    ...(suffix ? ["--suffix", suffix] : [])
  ]);
}

function rebind(workspace: Workspace, row: string, file: string, start: number, end: number, suffix?: string) {
  return uc(workspace, [
    "rebind", "--row", `probe.core.${row}`, "--file", file,
    "--mode", "explicit", "--start-line", String(start), "--end-line", String(end),
    ...(suffix ? ["--suffix", suffix] : [])
  ]);
}

function unbind(workspace: Workspace, row: string, extra: string[] = []) {
  return uc(workspace, ["unbind", "--row", `probe.core.${row}`, "--reason", "row_retired", ...extra]);
}

function scan(workspace: Workspace) {
  return uc(workspace, ["scan"]).envelope.data as {
    status: { rows: Array<{ row_id: string; status: string; local_status: string | null; current_binding_slugs: string[] }>; integrity_errors: unknown[] };
  };
}

function rowOf(workspace: Workspace, row: string) {
  return scan(workspace).status.rows.find((r) => r.row_id === `probe.core.${row}`);
}

function markers(workspace: Workspace, file: string): string[] {
  return readFileSync(join(workspace.dir, file), "utf8")
    .split("\n")
    .filter((line) => line.includes("@use-case:"));
}

function errorCodes(result: ReturnType<typeof bind>): string[] {
  return ((result.envelope.data as { errors?: Array<{ code: string }> }).errors ?? []).map((e) => e.code);
}

function registryLineCount(workspace: Workspace): number {
  return readFileSync(join(workspace.dir, ".use-cases", "bindings.jsonl"), "utf8")
    .trim()
    .split("\n")
    .filter(Boolean).length;
}

//: @use-case:lifecycle.bindings.rebind_repoints_a_binding#blackbox
describe("lifecycle.bindings.rebind_repoints_a_binding", () => {
  // golden_same_file. A marker on a declaration that cannot fail when its claim
  // does reads as proven from every angle the tool reports on. Being unable to
  // move it is the worst state a matrix can hold.
  test("the marker moves and the registration moves with it, appended not rewritten", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);
    const before = registryLineCount(workspace);

    const moved = rebind(workspace, "alpha", "src/alpha.ts", 5, 7);
    expect(moved.envelope.ok, `rebind failed: ${moved.stderr}`).toBe(true);
    const data = moved.envelope.data as { moved_from: { start_line: number }; registry_events_appended: number };
    expect(data.moved_from.start_line).toBe(1);
    // A release AND a re-registration: the ledger is only ever appended to.
    expect(data.registry_events_appended).toBe(2);
    expect(registryLineCount(workspace)).toBe(before + 2);
    expect(markers(workspace, "src/alpha.ts")).toHaveLength(2);
  });

  // golden_across_files.
  test("a binding moves between files, leaving no marker behind", () => {
    const workspace = makeWorkspace(["alpha", "beta"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);

    const moved = rebind(workspace, "alpha", "src/beta.ts", 1, 3);
    expect(moved.envelope.ok).toBe(true);
    expect(markers(workspace, "src/alpha.ts"), "the old file keeps nothing").toHaveLength(0);
    expect(markers(workspace, "src/beta.ts")).toHaveLength(2);
  });

  // bad_unresolvable_target. A rebind that cannot succeed changes NOTHING —
  // half-moving a binding would be worse than refusing.
  test("a target that cannot resolve leaves both the source and the ledger untouched", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);
    const linesBefore = registryLineCount(workspace);
    const sourceBefore = readFileSync(join(workspace.dir, "src", "alpha.ts"), "utf8");

    const moved = rebind(workspace, "alpha", "src/alpha.ts", 900, 902);
    expect(moved.envelope.ok).toBe(false);
    expect(errorCodes(moved)).toContain("BIND_SPAN_OUT_OF_RANGE");
    expect(registryLineCount(workspace)).toBe(linesBefore);
    expect(readFileSync(join(workspace.dir, "src", "alpha.ts"), "utf8")).toBe(sourceBefore);
  });

  // bad_unbound_row_is_refused. The refusal names the command that would work.
  test("rebinding a row that was never bound is refused and points at bind", () => {
    const workspace = makeWorkspace(["alpha"]);
    const moved = rebind(workspace, "alpha", "src/alpha.ts", 1, 3);

    expect(moved.envelope.ok).toBe(false);
    expect(errorCodes(moved)).toContain("NOT_REGISTERED");
    expect(JSON.stringify(moved.envelope.data), "the refusal names bind").toContain("use-cases bind");
  });

  // edge_verified_local_does_not_survive_the_move. A moved binding never
  // inherits the proof of the one it replaced.
  test("VERIFIED_LOCAL does not survive a rebind, and re-verifying restores it", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);
    uc(workspace, ["verify", "--row", "probe.core.alpha"]);
    expect(rowOf(workspace, "alpha")?.local_status).toBe("VERIFIED_LOCAL");

    rebind(workspace, "alpha", "src/alpha.ts", 5, 7);
    expect(rowOf(workspace, "alpha")?.local_status).toBe("STALE_LOCAL");

    uc(workspace, ["verify", "--row", "probe.core.alpha"]);
    expect(rowOf(workspace, "alpha")?.local_status).toBe("VERIFIED_LOCAL");
  });

  // edge_suffixed_binding_moves_alone.
  test("a row with two suffixed bindings moves only the one named", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3, "one");
    const second = bind(workspace, "alpha", "src/alpha.ts", 7, 9, "two");
    expect(second.envelope.ok, `second bind failed: ${second.stderr}`).toBe(true);

    const moved = rebind(workspace, "alpha", "src/alpha.ts", 9, 11, "two");
    expect(moved.envelope.ok).toBe(true);

    const lines = markers(workspace, "src/alpha.ts");
    expect(lines.filter((l) => l.includes("#one")), "#one must not have moved").toHaveLength(2);
    expect(lines.filter((l) => l.includes("#two"))).toHaveLength(2);
  });
});
//: @use-case:end lifecycle.bindings.rebind_repoints_a_binding#blackbox

//: @use-case:lifecycle.bindings.unbind_releases_a_registration#blackbox
describe("lifecycle.bindings.unbind_releases_a_registration", () => {
  // golden_clean. Removing a marker by hand never released its registration, so
  // a retired behaviour stayed registered forever and its slug could never be
  // bound again. This is that exit.
  test("the marker goes, the registration is released, and the slug is rebindable", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);

    expect(unbind(workspace, "alpha").envelope.ok).toBe(true);
    expect(markers(workspace, "src/alpha.ts")).toHaveLength(0);

    const again = bind(workspace, "alpha", "src/alpha.ts", 5, 7);
    expect(again.envelope.ok, "the same slug must bind again with no duplicate error").toBe(true);
    expect(errorCodes(again)).not.toContain("DUPLICATE_REGISTRATION");
  });

  // bad_unregistered_slug_is_refused.
  test("releasing a slug that is not registered is refused and writes nothing", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);
    const before = registryLineCount(workspace);

    const released = unbind(workspace, "alpha", ["--suffix", "nothing-here"]);
    expect(released.envelope.ok).toBe(false);
    expect(registryLineCount(workspace)).toBe(before);
  });

  // edge_already_stripped_by_hand. Hand-editing the source must never strand a
  // registration with no supported way out.
  test("a registration whose markers were removed by hand is still releasable", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);

    const path = join(workspace.dir, "src", "alpha.ts");
    writeFileSync(
      path,
      readFileSync(path, "utf8").split("\n").filter((l) => !l.includes("@use-case:")).join("\n")
    );

    expect(unbind(workspace, "alpha").envelope.ok, "a stripped source must still release").toBe(true);
  });

  // edge_dry_run_touches_nothing.
  test("a dry run reports the release without touching source or registry", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);
    const before = registryLineCount(workspace);

    const preview = unbind(workspace, "alpha", ["--dry-run"]);
    expect(preview.envelope.ok).toBe(true);
    expect((preview.envelope.data as { registry_event_appended: boolean }).registry_event_appended).toBe(false);
    expect(markers(workspace, "src/alpha.ts"), "the markers must still be there").toHaveLength(2);
    expect(registryLineCount(workspace)).toBe(before);
  });

  // edge_leaves_nothing_claiming_verified.
  test("unbinding leaves nothing behind claiming the row is verified", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);
    uc(workspace, ["verify", "--row", "probe.core.alpha"]);
    expect(rowOf(workspace, "alpha")?.local_status).toBe("VERIFIED_LOCAL");

    unbind(workspace, "alpha");
    const row = rowOf(workspace, "alpha");
    expect(row?.status).toBe("UNBOUND");
    expect(row?.local_status, "an unbound row claims no local proof").toBeNull();
  });

  // edge_one_suffixed_binding_of_two.
  test("releasing one suffixed binding leaves the other registered", () => {
    const workspace = makeWorkspace(["alpha"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3, "one");
    bind(workspace, "alpha", "src/alpha.ts", 7, 9, "two");

    expect(unbind(workspace, "alpha", ["--suffix", "one"]).envelope.ok).toBe(true);
    expect(rowOf(workspace, "alpha")?.current_binding_slugs).toEqual(["probe.core.alpha#two"]);
  });
});
//: @use-case:end lifecycle.bindings.unbind_releases_a_registration#blackbox

//: @use-case:lifecycle.bindings.retired_row_can_leave_the_matrix#blackbox
describe("lifecycle.bindings.retired_row_can_leave_the_matrix", () => {
  function deleteRow(workspace: Workspace, row: string): void {
    const path = join(workspace.dir, "use-cases", "probe.yml");
    const text = readFileSync(path, "utf8");
    const start = text.indexOf(`  - id: probe.core.${row}`);
    const next = text.indexOf("  - id: probe.core.", start + 1);
    writeFileSync(path, next === -1 ? text.slice(0, start) : text.slice(0, start) + text.slice(next));
  }

  // golden_retire. A retired behaviour must leave no permanent integrity error.
  test("a released binding whose row has left the matrix scans clean", () => {
    const workspace = makeWorkspace(["alpha", "beta"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);

    unbind(workspace, "alpha");
    deleteRow(workspace, "alpha");

    expect(scan(workspace).status.integrity_errors).toHaveLength(0);
  });

  // bad_still_bound_row_missing. Deleting the row WITHOUT releasing it first is
  // still an error, and the remediation names the supported way out rather than
  // telling anyone to edit the ledger.
  test("a row still bound but missing from the matrix is reported, and unbind is named", () => {
    const workspace = makeWorkspace(["alpha", "beta"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);
    deleteRow(workspace, "alpha");

    const { envelope } = runUcJson<{ status: { integrity_errors: Array<{ code: string }> } }>(
      ["scan", "--repo", "."],
      { cwd: workspace.dir, env: workspace.env }
    );
    const codes = envelope.data.status.integrity_errors.map((e) => e.code);
    expect(codes).toContain("REGISTRY_ROW_MISSING");
    expect(JSON.stringify(envelope.data), "the cure is unbind, not a ledger edit").toContain("unbind");
  });

  // edge_released_slug_with_no_marker. A release is not an absence: a slug that
  // was properly released must not then be reported as a missing marker.
  test("a released slug with no marker left is not reported as missing", () => {
    const workspace = makeWorkspace(["alpha", "beta"]);
    bind(workspace, "alpha", "src/alpha.ts", 1, 3);
    unbind(workspace, "alpha");

    const codes = (scan(workspace).status.integrity_errors as Array<{ code: string }>).map((e) => e.code);
    expect(codes).not.toContain("MISSING_MARKER");
    expect(codes).not.toContain("REGISTRY_ROW_MISSING");
  });
});
//: @use-case:end lifecycle.bindings.retired_row_can_leave_the_matrix#blackbox
