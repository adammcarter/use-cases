// The black-box oracle for mcp/resources.yml.
//
// These three rows had no row at all until row 1b wrote them, and no test until
// now: eight read-only resource URIs and four guided prompts, a third of the
// MCP surface. Driven over real stdio through tests/helpers/mcp-server.ts.
//
// Self-contained fixtures: a shared oracle file means one edit stales every row
// bound to it.
import { mkdirSync, mkdtempSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { McpSession } from "../helpers/mcp-server";

const tempDirs: string[] = [];
const sessions: McpSession[] = [];
afterAll(() => {
  for (const session of sessions) session.stop();
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
// matrix unusable, so every read would measure that instead of the behaviour.
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

function makeWorkspace(): string {
  const dir = mkdtempSync(join(tmpdir(), "uc-mcp-"));
  tempDirs.push(dir);
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), SEEDED_MATRIX);
  return dir;
}

async function session(dir: string, env: Record<string, string> = {}): Promise<McpSession> {
  const started = await McpSession.start(dir, { UCM_MCP_REPO: dir, ...env });
  sessions.push(started);
  return started;
}

/** Every file in the workspace, so a read can be proved not to have written. */
function snapshot(dir: string): string[] {
  const found: string[] = [];
  const walk = (current: string, prefix: string): void => {
    for (const entry of readdirSync(current)) {
      const full = join(current, entry);
      if (statSync(full).isDirectory()) walk(full, `${prefix}${entry}/`);
      else found.push(`${prefix}${entry}`);
    }
  };
  walk(dir, "");
  return found.sort();
}

const WORKSPACE_URIS = [
  "uc://matrix", "uc://matrix/status", "uc://freshness", "uc://bindings",
  "uc://ledger", "uc://evidence", "uc://schemas", "uc://config"
];

//: @use-case:mcp.resources.workspace_state_is_readable_and_read_only#blackbox
describe("mcp.resources.workspace_state_is_readable_and_read_only", () => {
  // golden_list_and_read.
  test("initialize advertises resources and prompts, and the expected URIs are listed and readable", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);

    expect(await mcp.capabilities()).toEqual(expect.arrayContaining(["prompts", "resources", "tools"]));

    const listed = await mcp.request("resources/list");
    const uris = (listed.result?.resources as Array<{ uri: string }>).map((r) => r.uri);
    expect(uris.sort()).toEqual([...WORKSPACE_URIS].sort());

    const read = await mcp.request("resources/read", { uri: "uc://matrix" });
    const contents = read.result?.contents as Array<{ mimeType: string; text: string }>;
    expect(contents[0].mimeType).toBe("application/json");
    expect(JSON.parse(contents[0].text)).toMatchObject({ command: "matrix.validate" });
  });

  // bad_unknown_resource.
  test("an unknown uc:// URI returns an error, not an empty success", async () => {
    const mcp = await session(makeWorkspace());
    const read = await mcp.request("resources/read", { uri: "uc://not-a-resource" });
    expect(read.error ?? read.result, "an unknown resource must not read as success").toBeTruthy();
    expect(JSON.stringify(read)).toMatch(/not.?found|unknown/i);
  });

  // bad_traversal_repo_path.
  test("a repo path that traverses out of the workspace is rejected", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);
    const read = await mcp.request("resources/read", { uri: "uc://matrix?repo=../../etc" });
    expect(JSON.stringify(read), "a traversal must not be followed").toMatch(/error|escape|invalid|not.?found/i);
  });

  // edge_no_read_mutates_state. Reading is safe in any session — that is what
  // makes these resources usable without a write gate.
  test("no repo-scoped read mutates workspace state", async () => {
    const dir = makeWorkspace();
    const mcp = await session(dir);
    const before = snapshot(dir);

    for (const uri of WORKSPACE_URIS) await mcp.request("resources/read", { uri });

    expect(snapshot(dir), "a read must leave the workspace byte-for-byte").toEqual(before);
  });
});
//: @use-case:end mcp.resources.workspace_state_is_readable_and_read_only#blackbox

//: @use-case:mcp.resources.schemas_are_readable_without_a_repo#blackbox
describe("mcp.resources.schemas_are_readable_without_a_repo", () => {
  // golden_named_schema and edge_index_lists_ids. The contract is what an
  // integrator depends on, and it does not belong to any one repo.
  test("the schema index and an individual schema read without any workspace", async () => {
    const bare = mkdtempSync(join(tmpdir(), "uc-mcp-bare-"));
    tempDirs.push(bare);
    const mcp = await McpSession.start(bare, {});
    sessions.push(mcp);

    const index = await mcp.request("resources/read", { uri: "uc://schemas" });
    const listed = JSON.parse((index.result?.contents as Array<{ text: string }>)[0].text) as {
      schemas: Array<{ id: string }>;
    };
    expect(listed.schemas.length).toBeGreaterThan(20);

    const name = listed.schemas[0].id.split("/").pop();
    const one = await mcp.request("resources/read", { uri: `uc://schemas/${name}` });
    expect(one.error, `reading uc://schemas/${name} must not error`).toBeUndefined();
    expect((one.result?.contents as Array<{ text: string }>)[0].text).toContain("$schema");
  });
});
//: @use-case:end mcp.resources.schemas_are_readable_without_a_repo#blackbox

//: @use-case:mcp.resources.prompts_guide_without_widening_the_surface#blackbox
describe("mcp.resources.prompts_guide_without_widening_the_surface", () => {
  // golden_list_and_get.
  test("the four guided prompts are listed and a get returns a grounded message", async () => {
    const mcp = await session(makeWorkspace());

    const listed = await mcp.request("prompts/list");
    const names = (listed.result?.prompts as Array<{ name: string }>).map((p) => p.name).sort();
    expect(names).toEqual(["uc/adopt-repo", "uc/bind-row", "uc/recover-suspect-row", "uc/release-review"]);

    const got = await mcp.request("prompts/get", { name: "uc/bind-row", arguments: { row: "probe.core.alpha" } });
    expect(got.error).toBeUndefined();
    expect(JSON.stringify(got.result), "the argument must reach the message").toContain("probe.core.alpha");
  });

  // bad_prove_is_never_exposed. A surface deliberately absent from the tools
  // must not be reachable through the prompts instead.
  test("prove is exposed by neither the tools nor the prompts", async () => {
    const mcp = await session(makeWorkspace());

    const tools = await mcp.request("tools/list");
    const toolNames = (tools.result?.tools as Array<{ name: string }>).map((t) => t.name);
    expect(toolNames.filter((n) => /prove/i.test(n)), "prove is CI-mediated, never an MCP tool").toEqual([]);

    const prompts = await mcp.request("prompts/list");
    expect(JSON.stringify(prompts.result), "nor may a prompt route to it").not.toMatch(/uc\/prove|prove-row/i);
  });

  // edge_unknown_prompt.
  test("an unknown prompt returns an error rather than an empty message", async () => {
    const mcp = await session(makeWorkspace());
    const got = await mcp.request("prompts/get", { name: "uc/not-a-prompt", arguments: {} });
    expect(got.error ?? JSON.stringify(got.result)).toBeTruthy();
    expect(JSON.stringify(got)).toMatch(/error|unknown|not.?found/i);
  });
});
//: @use-case:end mcp.resources.prompts_guide_without_widening_the_surface#blackbox
