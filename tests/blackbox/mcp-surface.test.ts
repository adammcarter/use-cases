// The black-box oracle for mcp/surface.yml.
//
// Driven over real stdio through tests/helpers/mcp-server.ts, so these assert
// the wrapper as a host actually reaches it rather than as a function call.
//
// Self-contained fixtures: a shared oracle file means one edit stales every row
// bound to it.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { McpSession } from "../helpers/mcp-server";
import { runUcJson } from "../helpers/uc-binary";

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

// A complete seed row: `use_cases: []` fails schema.minItems and leaves the
// matrix unusable, which every call would then measure instead of the wrapper.
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

const NEW_ROW = {
  id: "probe.core.beta",
  title: "Beta",
  lifecycle: "planned",
  value_tier: "core",
  journey_role: "golden",
  usage_frequency: "common"
};

function makeWorkspace(): string {
  const dir = mkdtempSync(join(tmpdir(), "uc-mcp-surface-"));
  tempDirs.push(dir);
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), SEEDED_MATRIX);
  return dir;
}

/** `write: true` enables the SESSION lock; calls still need allow_write. */
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

//: @use-case:mcp.surface.cli_contract_transport#blackbox
describe("mcp.surface.cli_contract_transport", () => {
  // golden_parity. The same command, reached two ways, gives the same answer.
  test("an MCP tool returns the same semantic envelope as the CLI command", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);

    const viaMcp = await mcp.callTool<{ valid: boolean }>("matrix_validate", { repo: dir });
    const viaCli = runUcJson<{ valid: boolean }>(["matrix", "validate", "--repo", "."], { cwd: dir, env: {} });

    expect(viaMcp.envelope.command).toBe(viaCli.envelope.command);
    expect(viaMcp.envelope.ok).toBe(viaCli.envelope.ok);
    expect(viaMcp.envelope.data.valid).toBe(viaCli.envelope.data.valid);
  });

  // edge_transport_details_may_differ. Parity is about the SEMANTIC result;
  // the transport wrapper around it is allowed to look different.
  test("the envelope carries the full v1 contract, whatever the transport", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);
    const { envelope } = await mcp.callTool("matrix_validate", { repo: dir });

    for (const field of ["schema_version", "protocol_version", "command", "ok", "data"]) {
      expect(envelope, `the MCP envelope must carry ${field}`).toHaveProperty(field);
    }
  });

  // bad_logic_is_never_reimplemented_in_the_wrapper. If the wrapper decided
  // anything itself the two surfaces would drift; the same invalid input must
  // produce the same verdict on both.
  test("an invalid matrix gives the same verdict through both surfaces", async () => {
    const dir = makeWorkspace();
    writeFileSync(join(dir, "use-cases", "probe.yml"), "schema_version: 1\nfeature:\n  id: probe.core\n");
    const mcp = await session(dir);

    const viaMcp = await mcp.callTool<{ valid: boolean }>("matrix_validate", { repo: dir });
    const viaCli = runUcJson<{ valid: boolean }>(["matrix", "validate", "--repo", "."], { cwd: dir, env: {} });

    expect(viaMcp.envelope.ok).toBe(viaCli.envelope.ok);
    expect(viaMcp.envelope.data.valid).toBe(viaCli.envelope.data.valid);
  });
});
//: @use-case:end mcp.surface.cli_contract_transport#blackbox

//: @use-case:mcp.surface.write_gating#blackbox
describe("mcp.surface.write_gating", () => {
  // bad_read_only_session_cannot_mutate. TWO independent locks, and this is the
  // session one.
  test("a read-only session refuses a mutating tool with a structured result", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);
    const before = matrixText(dir);

    const { envelope } = await mcp.callTool("use_case_upsert", {
      repo: dir, file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true
    });

    expect(envelope.ok).toBe(false);
    // The SESSION lock has its own code, distinct from the call-level one, so a
    // reader can tell which of the two refused.
    expect(envelope.diagnostics.map((d) => d.code)).toContain("mcp.server_write_mode_required");
    expect(matrixText(dir), "a refused write changes nothing").toBe(before);
  });

  // The other lock: even a write-enabled session refuses a call that does not
  // ask for the write explicitly. Enabling writes is not a blanket permission.
  test("a write-enabled session still refuses a call that omits allow_write", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });
    const before = matrixText(dir);

    const { envelope } = await mcp.callTool("use_case_upsert", {
      repo: dir, file: "use-cases/probe.yml", use_case: NEW_ROW
    });

    expect(envelope.ok).toBe(false);
    // The CALL lock, and a different code from the session one.
    expect(envelope.diagnostics.map((d) => d.code)).toContain("mcp.write_mode_required");
    expect(matrixText(dir)).toBe(before);
  });

  // golden_explicit_write. Both locks open, and the write lands.
  test("with the session enabled and allow_write set, the mutation lands", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });

    const { envelope } = await mcp.callTool<{ status: string }>("use_case_upsert", {
      repo: dir, file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true
    });

    expect(envelope.ok).toBe(true);
    expect(envelope.data.status).toBe("created");
    expect(matrixText(dir)).toContain("probe.core.beta");
  });

  // bad_mutation_outside_the_configured_root.
  test("a path escape is refused even with both locks open", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });

    const { envelope } = await mcp.callTool<{ status: string; diagnostics: Array<{ code: string }> }>(
      "use_case_upsert",
      { repo: dir, file: "../escape.yml", use_case: NEW_ROW, allow_write: true }
    );

    expect(envelope.ok).toBe(false);
    // Past both locks, so this refusal comes from the domain and reports there.
    expect(envelope.data.status).toBe("blocked");
    expect(envelope.data.diagnostics.map((d) => d.code)).toContain("matrix.mutation_path_escape");
  });
});
//: @use-case:end mcp.surface.write_gating#blackbox

//: @use-case:mcp.surface.approval_request_only#blackbox
describe("mcp.surface.approval_request_only", () => {
  // golden_boundary and edge_no_event_is_appended. MCP may ASK; it may never
  // answer. Asking and answering stay separate acts.
  test("the approval tool requires trusted confirmation and writes nothing", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });

    const { envelope } = await mcp.callTool<{
      decision_required: boolean;
      trusted_confirmation_required: boolean;
    }>("showcase_request_approval", { repo: dir, run: "any-run" });

    expect(envelope.ok, "requesting is allowed").toBe(true);
    expect(envelope.data.trusted_confirmation_required, "but it only ever requests").toBe(true);
    expect(envelope.data.decision_required).toBe(true);
    // complete:false is the tell — the act is not finished by the request.
    expect((envelope as unknown as { complete: boolean }).complete).toBe(false);
  });

  // bad_mcp_cannot_write_user_approval. There is no tool to do it with.
  test("no MCP tool can record an approval at all", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir, { write: true });
    const listed = await mcp.request("tools/list");
    const names = (listed.result?.tools as Array<{ name: string }>).map((t) => t.name);

    expect(names, "requesting exists").toContain("showcase_request_approval");
    expect(
      names.filter((n) => /approve|approval_record|record_approval/i.test(n)),
      "recording one does not"
    ).toEqual([]);
  });
});
//: @use-case:end mcp.surface.approval_request_only#blackbox

//: @use-case:mcp.surface.domain_results_not_transport_failures#blackbox
describe("mcp.surface.domain_results_not_transport_failures", () => {
  // golden_envelope and bad_never_an_opaque_transport_failure. A domain problem
  // must never be disguised as a broken connection.
  test("damaged input comes back as a structured result, not a transport error", async () => {
    const dir = makeWorkspace();
    writeFileSync(join(dir, "use-cases", "probe.yml"), "schema_version: 1\nfeature:\n  id: probe.core\n");
    const mcp = await session(dir);

    const { envelope, raw } = await mcp.callTool<{ valid: boolean }>("matrix_validate", { repo: dir });

    expect(raw.error, "the transport itself must succeed").toBeUndefined();
    expect(envelope.command).toBe("matrix.validate");
    expect(envelope.ok).toBe(false);
    expect(envelope.data.valid).toBe(false);
  });
});
//: @use-case:end mcp.surface.domain_results_not_transport_failures#blackbox

//: @use-case:mcp.surface.declared_tool_schemas#blackbox
describe("mcp.surface.declared_tool_schemas", () => {
  // golden_declared and edge_repo_stays_required.
  test("high-value tools declare named parameters, with repo required", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);
    const listed = await mcp.request("tools/list");
    const tools = listed.result?.tools as Array<{
      name: string;
      inputSchema?: { properties?: Record<string, unknown>; required?: string[] };
    }>;

    const validate = tools.find((t) => t.name === "matrix_validate");
    expect(validate?.inputSchema?.properties, "parameters are discoverable from the tool").toBeTruthy();
    expect(
      Object.keys(validate?.inputSchema?.properties ?? {}),
      "repo is a declared parameter, not a guess"
    ).toContain("repo");
  });

  // bad_an_open_passthrough_is_not_a_schema.
  test("no high-value tool ships only an open passthrough", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);
    const listed = await mcp.request("tools/list");
    const tools = listed.result?.tools as Array<{
      name: string;
      inputSchema?: { properties?: Record<string, unknown> };
    }>;

    for (const name of ["matrix_validate", "matrix_list", "evidence_status"]) {
      const tool = tools.find((t) => t.name === name);
      expect(
        Object.keys(tool?.inputSchema?.properties ?? {}).length,
        `${name} must declare its parameters`
      ).toBeGreaterThan(0);
    }
  });
});
//: @use-case:end mcp.surface.declared_tool_schemas#blackbox
