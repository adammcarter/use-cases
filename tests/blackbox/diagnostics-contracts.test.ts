// The black-box oracle for diagnostics/contracts.yml.
//
// Four of the file's five rows. The fifth, missing_build_hint, is deliberately
// absent: it fires on the path where the COMPILED CORE is missing, and the
// shipped bundle is self-contained so it never takes that path. Driving it
// through the binary would mean dismantling the build, which measures the
// harness rather than the behaviour. It stays on its white-box verifier until
// the Swift cut-over gives it an equivalent.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { runUc, runUcJson } from "../helpers/uc-binary";

const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

// NOT an empty `use_cases: []` — that fails schema.minItems, leaving the matrix
// `unusable`, so anything that then calls `matrix validate` would be asserting
// against a workspace that can never be valid.
const SEEDED_MATRIX = `schema_version: 1
feature:
  id: probe.core
  name: Probe
  summary: Probe.
use_cases:
  - id: probe.core.alpha
    title: Alpha
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so the matrix is valid.
    preconditions: [Nothing.]
    trigger: Nothing.
    scenarios:
      - id: probe.core.alpha.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [It passes.]
    observable_outcomes: [It exists.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`;

function config(dataRoot: string): string {
  return `schema_version: 1
workspace_id: probe
component_id: probe
data_root: ${dataRoot}
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
`;
}

/** A workspace whose data root may sit somewhere other than the repo root. */
function makeWorkspace(dataRoot = "."): { dir: string; env: Record<string, string> } {
  const dir = mkdtempSync(join(tmpdir(), "uc-diagnostics-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  writeFileSync(join(dir, "use-cases.yml"), config(dataRoot));
  const matrixDir = dataRoot === "." ? join(dir, "use-cases") : join(dir, dataRoot, "use-cases");
  mkdirSync(matrixDir, { recursive: true });
  writeFileSync(join(matrixDir, "probe.yml"), SEEDED_MATRIX);
  return { dir, env };
}

describe("diagnostics.contracts.root_resolution", () => {
  // golden_doctor. The two roots are separate facts, not one path.
  test("doctor roots reports the workspace root and the data root distinctly", () => {
    const workspace = makeWorkspace();
    const { envelope } = runUcJson<{
      workspace_root: string;
      data_root: string;
      use_cases_root: string;
      provenance: Record<string, string>;
    }>(["doctor", "roots", "--repo", "."], { cwd: workspace.dir, env: workspace.env });

    expect(envelope.ok).toBe(true);
    expect(envelope.data.workspace_root).toBeTruthy();
    expect(envelope.data.data_root).toBeTruthy();
    expect(envelope.data.use_cases_root).toContain("use-cases");
    expect(envelope.data.provenance, "where each root came from is reported too").toBeTruthy();
  });

  // edge_separated_data_root_resolves. The monorepo and CI layouts this exists
  // for: the data root moves without breaking the paths built from it.
  test("a data root below the repo root resolves, and the matrix path follows it", () => {
    const workspace = makeWorkspace("sub");
    const { envelope } = runUcJson<{ workspace_root: string; data_root: string; use_cases_root: string }>(
      ["doctor", "roots", "--repo", "."],
      { cwd: workspace.dir, env: workspace.env }
    );

    expect(envelope.ok).toBe(true);
    expect(envelope.data.data_root).not.toBe(envelope.data.workspace_root);
    expect(envelope.data.data_root.endsWith("/sub")).toBe(true);
    expect(envelope.data.use_cases_root).toContain("/sub/use-cases");

    // And the relocated root actually works, rather than merely being reported.
    const validated = runUcJson<{ valid: boolean }>(["matrix", "validate", "--repo", "."], {
      cwd: workspace.dir,
      env: workspace.env
    });
    expect(validated.envelope.data.valid).toBe(true);
  });

  // bad_unsafe_or_symlinked_root_is_refused. A data root that climbs out of the
  // repo is refused rather than silently followed.
  test("a data root pointing outside the repo is refused", () => {
    const workspace = makeWorkspace();
    writeFileSync(join(workspace.dir, "use-cases.yml"), config("../escape"));

    const { envelope } = runUcJson(["doctor", "roots", "--repo", "."], {
      cwd: workspace.dir,
      env: workspace.env
    });
    expect(envelope.ok).toBe(false);
    expect(JSON.stringify(envelope.diagnostics)).toContain("workspace_config");
  });
});

describe("diagnostics.contracts.schema_contract_surface", () => {
  // golden_validate. The contract is enumerable and its fixtures validate, so
  // an integrator can depend on it.
  test("schema list enumerates the published v1 schemas and the fixtures validate", () => {
    const listed = runUcJson<{ schemas: Array<{ id: string }> }>(["schema", "list"]);
    expect(listed.envelope.ok).toBe(true);
    expect(listed.envelope.data.schemas.length).toBeGreaterThan(20);
    for (const schema of listed.envelope.data.schemas) {
      expect(schema.id, "every schema is published under a versioned id").toMatch(
        /^https:\/\/use-cases\.dev\/schemas\/v1\//
      );
    }

    const fixtures = runUcJson<{ validated_schema_ids: string[] }>(["schema", "validate-fixtures"]);
    expect(fixtures.envelope.ok).toBe(true);
    expect(fixtures.envelope.data.validated_schema_ids.length).toBeGreaterThan(0);
  });

  // edge_cli_and_mcp_validate_against_the_same_ids. The envelope every command
  // emits is itself one of the published schemas — one contract, not two.
  test("the result envelope every command emits is one of the published schemas", () => {
    const listed = runUcJson<{ schemas: Array<{ id: string }> }>(["schema", "list"]);
    const ids = listed.envelope.data.schemas.map((s) => s.id);
    expect(ids).toContain("https://use-cases.dev/schemas/v1/cli-result.schema.json");

    // And a real envelope carries the fields that schema describes.
    const version = runUcJson(["version"]);
    for (const field of ["schema_version", "protocol_version", "command", "ok", "complete", "data", "diagnostics", "context"]) {
      expect(version.envelope, `envelope must carry ${field}`).toHaveProperty(field);
    }
  });

  // bad_a_drifted_result_fails_validation. The fixture set is the guard: if a
  // result shape drifts from its declared schema, this is what goes red.
  test("validate-fixtures reports the fixture it checked, so drift has somewhere to fail", () => {
    const { envelope } = runUcJson<{ fixture: string; validated_schema_ids: string[] }>([
      "schema", "validate-fixtures"
    ]);
    expect(envelope.ok).toBe(true);
    expect(envelope.data.fixture, "the checked fixture is named").toBeTruthy();
    expect(envelope.diagnostics, "a clean run reports no drift").toHaveLength(0);
  });
});

describe("diagnostics.contracts.identity_consistency", () => {
  // golden_envelope.
  test("every envelope reports the configured component id", () => {
    for (const args of [["version"], ["schema", "list"]]) {
      const { envelope } = runUcJson(args);
      expect(
        (envelope.context as { component_id?: string }).component_id,
        `${args.join(" ")} must report the component id`
      ).toBe("use-cases");
    }
  });

  // edge_unconfigured_workspace_uses_the_default. A workspace with no config
  // still reports use-cases rather than nothing or a stale name.
  test("an unconfigured workspace still defaults to use-cases", () => {
    const bare = mkdtempSync(join(tmpdir(), "uc-unconfigured-"));
    tempDirs.push(bare);
    const { envelope } = runUcJson(["version", "--repo", "."], { cwd: bare, env: {} });
    expect((envelope.context as { component_id?: string }).component_id).toBe("use-cases");
  });

  // bad_no_stale_product_name_survives_anywhere. The rename this row exists to
  // protect: a published build must never leak the pre-rename name.
  test("no envelope leaks the pre-rename product name", () => {
    for (const args of [["version"], ["schema", "list"]]) {
      const raw = JSON.stringify(runUcJson(args).envelope).toLowerCase();
      expect(raw, `${args.join(" ")} leaked a stale product name`).not.toContain("ucase-matrix");
      expect(raw).not.toContain("usecase-matrix");
    }
  });
});

describe("diagnostics.contracts.cli_self_documents", () => {
  // golden_usage. An agent can discover the surface from the CLI itself.
  test("a bare invocation and --help both print usage listing the commands", () => {
    const bare = runUcJson<{ usage: string }>([]);
    expect(bare.envelope.command).toBe("help");
    expect(bare.envelope.data.usage, "the usage line is in the envelope").toContain("use-cases <command>");

    const help = runUc(["--help"]);
    expect(help.status).toBe(0);
    expect(help.stdout).toContain("use-cases — the Use Cases CLI");
    for (const command of ["scan", "verify", "bind"]) {
      expect(help.stdout, `help must list ${command}`).toContain(command);
    }
  });

  // bad_unrecognized_command_is_not_a_bare_refusal. An unknown command gets
  // usage, not a dead end.
  test("an unrecognised command answers with usage naming what was not recognised", () => {
    const { envelope } = runUcJson(["frobnicate"]);
    expect(envelope.ok).toBe(false);
    expect(envelope.command, "it answers as help rather than command.unknown").toBe("help");

    const human = runUc(["frobnicate"]);
    expect(human.stdout + human.stderr).toContain("frobnicate");
    expect(human.stdout + human.stderr).toContain("use-cases --help");
  });
});
