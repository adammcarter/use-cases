// The black-box oracle for mcp/wrapper.yml.
//
// Two rows about MCP mutating the matrix safely and preserving showcase
// parity, driven over real stdio through tests/helpers/mcp-server.ts.
//
// Self-contained fixtures: a shared oracle file means one edit stales every
// row bound to it.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { McpSession } from "../helpers/mcp-server";

const tempDirs: string[] = [];
const sessions: McpSession[] = [];
afterAll(() => {
  for (const s of sessions) s.stop();
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

// A complete seed row: `use_cases: []` fails schema.minItems, and mutation is
// refused outright against an incomplete matrix.
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
    intent: Exist so the matrix is complete enough to mutate.
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

const NEW_ROW = {
  id: "probe.core.beta",
  title: "Beta",
  lifecycle: "planned",
  value_tier: "core",
  journey_role: "golden",
  usage_frequency: "common"
};

function makeWorkspace(): string {
  const dir = mkdtempSync(join(tmpdir(), "uc-mcp-wrapper-"));
  tempDirs.push(dir);
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), SEEDED_MATRIX);
  return dir;
}

async function session(dir: string, options: { write?: boolean } = {}): Promise<McpSession> {
  const env: Record<string, string> = { UCM_MCP_REPO: dir };
  if (options.write) env.UCM_MCP_WRITE = "1";
  const started = await McpSession.start(dir, env);
  sessions.push(started);
  return started;
}

function matrixText(dir: string): string {
  return readFileSync(join(dir, "use-cases", "probe.yml"), "utf8");
}

describe("mcp.use_case_mutation.safe", () => {
  // golden_upsert. The matrix must still be complete AFTER the write, not just
  // before it — otherwise the wrapper could leave a workspace it cannot fix.
  test("upsert through MCP returns a matrix.upsert envelope and leaves the matrix valid", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });

    const { envelope } = await mcp.callTool<{ status: string }>("use_case_upsert", {
      repo: dir, file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true
    });
    expect(envelope.command).toBe("matrix.upsert");
    expect(envelope.ok).toBe(true);
    expect(envelope.data.status).toBe("created");

    const validated = await mcp.callTool<{ valid: boolean }>("matrix_validate", { repo: dir });
    expect(validated.envelope.data.valid, "the matrix stays complete after the write").toBe(true);
  });

  // golden_remove. Delete is a lifecycle transition, not a deletion.
  test("remove through MCP marks the row removed rather than deleting it", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });
    await mcp.callTool("use_case_upsert", {
      repo: dir, file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true
    });

    const { envelope } = await mcp.callTool<{ status: string }>("use_case_remove", {
      repo: dir, use_case: "probe.core.beta", reason: "retired", allow_write: true
    });
    expect(envelope.command).toBe("matrix.remove");
    expect(envelope.ok).toBe(true);

    const text = matrixText(dir);
    expect(text, "the row survives as history").toContain("probe.core.beta");
    expect(text).toContain("lifecycle: removed");
  });

  // bad_write_without_write_mode. Two independent locks: the session and the
  // call. Missing either is refused.
  test("write mode is required before any mutation, at both the session and the call", async () => {
    const readOnly = makeWorkspace();
    const readOnlySession = await session(readOnly);
    const refusedBySession = await readOnlySession.callTool("use_case_upsert", {
      repo: readOnly, file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true
    });
    expect(refusedBySession.envelope.ok).toBe(false);
    expect(
      refusedBySession.envelope.diagnostics.map((d) => d.code),
      "the session lock reports its own code"
    ).toContain("mcp.server_write_mode_required");

    const enabled = makeWorkspace();
    const enabledSession = await session(enabled, { write: true });
    const refusedByCall = await enabledSession.callTool("use_case_upsert", {
      repo: enabled, file: "use-cases/probe.yml", use_case: NEW_ROW
    });
    expect(refusedByCall.envelope.ok, "enabling writes is not a blanket permission").toBe(false);
    expect(
      refusedByCall.envelope.diagnostics.map((d) => d.code),
      "and the call lock reports a DIFFERENT one"
    ).toContain("mcp.write_mode_required");
  });

  // bad_path_escape_or_damaged_matrix.
  test("a path escape and a damaged matrix each prevent mutation", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });

    const escaped = await mcp.callTool<{ status: string; diagnostics: Array<{ code: string }> }>(
      "use_case_upsert",
      { repo: dir, file: "../escape.yml", use_case: NEW_ROW, allow_write: true }
    );
    expect(escaped.envelope.ok).toBe(false);
    expect(escaped.envelope.data.diagnostics.map((d) => d.code)).toContain("matrix.mutation_path_escape");

    const damaged = makeWorkspace();
    writeFileSync(join(damaged, "use-cases", "probe.yml"), "schema_version: 1\nfeature:\n  id: probe.core\n");
    const damagedSession = await session(damaged, { write: true });
    const refused = await damagedSession.callTool<{ status: string }>("use_case_upsert", {
      repo: damaged, file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true
    });
    expect(refused.envelope.ok, "a damaged matrix cannot be edited further").toBe(false);
  });
});

describe("mcp.wrapper.parity", () => {
  // golden_cli and edge_compiled_stdio_loads_the_packaged_core. Parity has to
  // hold for the artifact that actually ships, which is why this drives the
  // COMPILED server over stdio rather than calling into the module.
  test("the compiled server over stdio returns CLI envelopes for the showcase family", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);

    const planned = await mcp.callTool<{ plan_id?: string }>("plan_showcase", { repo: dir });
    expect(planned.envelope.command, "a CLI command name, not an MCP one").toContain("plan");
    expect(planned.raw.error, "the transport succeeds").toBeUndefined();

    const status = await mcp.callTool("matrix_status", { repo: dir });
    expect(status.envelope).toHaveProperty("schema_version");
    expect(status.envelope).toHaveProperty("command");
  });

  // bad_approval_stays_pending. MCP requests approval; it never appends it.
  test("requesting approval through MCP leaves it pending", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });

    const { envelope } = await mcp.callTool<{ trusted_confirmation_required: boolean }>(
      "showcase_request_approval",
      { repo: dir, run: "any-run" }
    );
    expect(envelope.data.trusted_confirmation_required).toBe(true);
    expect((envelope as unknown as { complete: boolean }).complete, "asking does not finish the act").toBe(false);
  });
});
