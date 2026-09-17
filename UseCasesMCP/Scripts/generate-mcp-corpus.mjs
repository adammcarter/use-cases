// Regenerates the MCP corpus by driving the REAL TypeScript server over stdio,
// and recording exactly the response line it wrote for each request line.
//
//   pnpm build
//   node UseCasesMCP/Scripts/generate-mcp-corpus.mjs
//
// Written:
//
//   Tests/UseCasesMCPTests/Server/McpGoldenCorpus.swift
//     For each case: the sandbox's files before the run, the environment the
//     server was started with, every request line sent, the response line it
//     answered with (null when it answered with silence), and the sandbox's
//     files afterwards for a case that writes.
//
// Determinism. Every appending tool that takes a `recorded_at`,
// `generated_at` or `idempotency_key` is given one, so the showcase ledger's
// ids derive from pinned inputs rather than the clock. What is left is
// genuinely nondeterministic and is normalised, nothing else:
//
//   * absolute sandbox paths      -> $SANDBOX
//   * the approval request's own
//     nonce and validity window   -> $JTI / $IAT / $EXP
//   * a generation instant        -> $NOW  (generated_at, evaluated_at)
//   * an evidence event's UUIDv7
//     and its ledger shard        -> $UUID / $SHARD
//   * the clock stamps of the one
//     tool that cannot pin them,
//     `evidence_record`           -> $NOW  (recorded_at, captured_at), named
//                                   per case in `clock_fields`
//
// Non-ASCII output is carried as JSON escapes, so the file stays ASCII.
import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const serverEntry = join(repositoryRoot, "dist/uc-mcp.js");
const outputDirectory = join(packageRoot, "Tests/UseCasesMCPTests/Server");

for (const source of ["packages/mcp/src/index.ts", "packages/mcp/src/tools.ts", "packages/mcp/src/toolHandlers.ts", "packages/mcp/src/toolSchemas.ts", "packages/mcp/src/resources.ts", "packages/mcp/src/prompts.ts"]) {
  if (statSync(serverEntry).mtimeMs < statSync(join(repositoryRoot, source)).mtimeMs) {
    throw new Error(`dist/uc-mcp.js is older than ${source}; run pnpm build first`);
  }
}

const CONFIG = `schema_version: 1
workspace_id: probe
component_id: probe
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
`;

const MATRIX = `schema_version: 1
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

const DAMAGED = "schema_version: 1\nfeature:\n  id: probe.core\n";

const workspace = { "use-cases.yml": CONFIG, "use-cases/probe.yml": MATRIX };
const damaged = { "use-cases.yml": CONFIG, "use-cases/probe.yml": DAMAGED };
const bare = {};

const S = "$SANDBOX";
const AT = "2026-06-25T12:00:00.000Z";

let nextId = 0;
function request(method, params) {
  nextId += 1;
  return JSON.stringify({ jsonrpc: "2.0", id: nextId, method, params });
}

function call(name, args) {
  return request("tools/call", { name, arguments: args });
}

/** A workspace-scoped tool call against the sandbox. */
function repoCall(name, args = {}) {
  return call(name, { repo: S, ...args });
}

const NEW_ROW = {
  id: "probe.core.beta",
  title: "Beta",
  lifecycle: "planned",
  value_tier: "core",
  journey_role: "golden",
  usage_frequency: "common"
};

const initialize = request("initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "use-cases-corpus", version: "0" }
});

// Each case: [name, files, env, requests, { filesAfter? }]. A request may be a
// function of the responses so far, so a run id minted by an earlier call can
// be named by a later one; the resolved line is what gets recorded.
const cases = [
  // ---- the handshake and the protocol frame
  ["initialize", bare, {}, [initialize]],
  ["initialize_twice_is_answered_twice", bare, {}, [initialize, initialize]],
  ["initialize_unknown_protocol_version_is_not_negotiated", bare, {}, [
    request("initialize", { protocolVersion: "1999-01-01", capabilities: {}, clientInfo: { name: "x", version: "0" } })
  ]],
  ["initialized_notification_is_silent", bare, {}, [
    JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized", params: {} })
  ]],
  ["blank_line_is_silent", bare, {}, ["   "]],
  ["parse_error", bare, {}, ["not json at all"]],
  ["unknown_method", bare, {}, [request("nope/thing", {})]],
  ["missing_method", bare, {}, [JSON.stringify({ jsonrpc: "2.0", id: 99 })]],
  ["method_without_id_is_answered_with_null", bare, {}, [JSON.stringify({ jsonrpc: "2.0", method: "tools/list" })]],
  ["string_id_is_echoed", bare, {}, [JSON.stringify({ jsonrpc: "2.0", id: "abc", method: "tools/list", params: {} })]],
  ["tools_list", bare, {}, [request("tools/list", {})]],
  ["resources_list", bare, {}, [request("resources/list", {})]],
  ["prompts_list", bare, {}, [request("prompts/list", {})]],

  // ---- the gates, in the order they are checked
  ["tool_unknown", workspace, {}, [call("not_a_tool", { repo: S })]],
  ["tool_timeout_zero", workspace, {}, [repoCall("matrix_validate", { timeout_ms: 0 })]],
  ["tool_timeout_nonzero_is_advisory", workspace, {}, [repoCall("matrix_validate", { timeout_ms: 1 })]],
  ["write_without_allow_write", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("use_case_upsert", { file: "use-cases/probe.yml", use_case: NEW_ROW })
  ]],
  ["write_without_server_write_mode", workspace, {}, [
    repoCall("use_case_upsert", { file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true })
  ]],
  ["capsule_run_needs_command_execution_mode", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("capsule_run", { capsule: "probe", execute_commands: true, allow_write: true })
  ]],
  ["trusted_user_claim_actor_type", workspace, {}, [repoCall("matrix_validate", { actor_type: "user" })]],
  ["trusted_user_claim_approver_type", workspace, {}, [repoCall("matrix_validate", { approver_type: "user" })]],
  ["trusted_user_claim_trusted_confirmation", workspace, {}, [
    repoCall("matrix_validate", { trusted_confirmation: "user" })
  ]],
  ["missing_repo", workspace, {}, [call("matrix_validate", {})]],
  ["empty_repo_is_missing", workspace, {}, [call("matrix_validate", { repo: "" })]],
  ["repo_not_found", workspace, {}, [call("matrix_validate", { repo: `${S}/nowhere` })]],
  ["data_root_escapes_repo", workspace, {}, [repoCall("matrix_validate", { data_root: "../elsewhere" })]],
  ["data_root_inside_repo", workspace, {}, [repoCall("matrix_validate", { data_root: "." })]],

  // ---- the read-only tools
  ["doctor_roots", workspace, {}, [repoCall("doctor_roots")]],
  ["doctor_roots_bare_workspace", bare, {}, [repoCall("doctor_roots")]],
  ["matrix_validate", workspace, {}, [repoCall("matrix_validate")]],
  ["matrix_validate_damaged", damaged, {}, [repoCall("matrix_validate")]],
  ["matrix_validate_bare", bare, {}, [repoCall("matrix_validate")]],
  ["matrix_list", workspace, {}, [repoCall("matrix_list")]],
  ["matrix_list_filtered", workspace, {}, [
    repoCall("matrix_list", { value: ["core"], journey_role: ["golden"], lifecycle: ["active"], host: ["codex.cli"] })
  ]],
  ["matrix_list_filter_excludes_everything", workspace, {}, [repoCall("matrix_list", { value: ["long_tail"] })]],
  ["matrix_list_single_string_filter", workspace, {}, [repoCall("matrix_list", { tag: "nothing" })]],
  ["matrix_list_strict_on_damaged", damaged, {}, [repoCall("matrix_list", { strict: true })]],
  ["matrix_status", workspace, {}, [repoCall("matrix_status")]],
  ["matrix_status_damaged", damaged, {}, [repoCall("matrix_status")]],
  ["evidence_status", workspace, {}, [repoCall("evidence_status")]],
  ["plan_showcase", workspace, {}, [repoCall("plan_showcase", { generated_at: AT })]],
  ["plan_showcase_strict_damaged", damaged, {}, [repoCall("plan_showcase", { generated_at: AT, strict: true })]],
  ["plan_showcase_bounded", workspace, {}, [
    repoCall("plan_showcase", { generated_at: AT, audience: "owner", timebox_seconds: 120, max_items: 1, host: "claude.cli" })
  ]],
  ["plan_walkthrough", workspace, {}, [repoCall("plan_walkthrough", { generated_at: AT })]],
  ["showcase_status_unknown_run", workspace, {}, [repoCall("showcase_status", { run: "nope" })]],
  ["showcase_status_missing_run", workspace, {}, [call("showcase_status", { repo: S })]],
  ["showcase_status_unsafe_run", workspace, {}, [repoCall("showcase_status", { run: "../escape" })]],
  ["showcase_request_approval_unstarted", workspace, {}, [repoCall("showcase_request_approval", { run: "nope" })]],
  ["capsule_run_missing_capsule", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("capsule_run", { allow_write: true })
  ]],
  ["capsule_run_unknown_capsule", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("capsule_run", { capsule: "nope", allow_write: true, recorded_at: AT, idempotency_key: "corpus:capsule" })
  ]],

  // ---- the mutating tools
  ["use_case_upsert", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("use_case_upsert", { file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true }),
    repoCall("matrix_validate")
  ], { filesAfter: ["use-cases/probe.yml"] }],
  ["use_case_upsert_path_escape", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("use_case_upsert", { file: "../escape.yml", use_case: NEW_ROW, allow_write: true })
  ]],
  ["use_case_upsert_damaged_matrix", damaged, { UCM_MCP_WRITE: "1" }, [
    repoCall("use_case_upsert", { file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true })
  ]],
  ["use_case_upsert_missing_arguments", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("use_case_upsert", { file: "use-cases/probe.yml", allow_write: true })
  ]],
  ["use_case_remove", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("use_case_upsert", { file: "use-cases/probe.yml", use_case: NEW_ROW, allow_write: true }),
    repoCall("use_case_remove", { use_case: "probe.core.beta", reason: "retired", allow_write: true })
  ], { filesAfter: ["use-cases/probe.yml"] }],
  ["use_case_remove_missing_arguments", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("use_case_remove", { use_case: "probe.core.beta", allow_write: true })
  ]],
  ["use_case_remove_unknown_row", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("use_case_remove", { use_case: "probe.core.nope", reason: "retired", allow_write: true })
  ]],
  ["evidence_record", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("evidence_record", {
      use_case: "probe.core.alpha",
      kind: "agent_observation",
      result: "pass",
      summary: "Watched it run.",
      idempotency_key: "corpus:evidence:one",
      allow_write: true
    }),
    repoCall("evidence_status")
  ], { clockFields: ["recorded_at", "captured_at"] }],
  ["evidence_record_defaults", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("evidence_record", { use_case: "probe.core.alpha", idempotency_key: "corpus:evidence:two", allow_write: true })
  ], { clockFields: ["recorded_at", "captured_at"] }],
  ["evidence_record_missing_use_case", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("evidence_record", { allow_write: true })
  ]],
  ["evidence_record_unresolved_use_case", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("evidence_record", { use_case: "probe.core.nope", allow_write: true })
  ]],
  ["evidence_void_missing_arguments", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("evidence_void", { evidence: "probe.core.alpha", allow_write: true })
  ]],
  ["evidence_void_unsafe_id", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("evidence_void", { evidence: "../escape", expected_head: "x", reason: "why", allow_write: true })
  ]],

  // ---- a whole showcase run, each step naming the run the last one minted
  ["showcase_run_lifecycle", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("showcase_start", {
      select: "probe.core.alpha",
      generated_at: AT,
      recorded_at: AT,
      idempotency_key: "corpus:start",
      allow_write: true
    }),
    (previous) => repoCall("showcase_status", { run: runIdOf(previous[0]) }),
    (previous) => repoCall("showcase_record_observation", {
      run: runIdOf(previous[0]),
      item: itemIdOf(previous[0]),
      text: "It ran.",
      recorded_at: "2026-06-25T12:01:00.000Z",
      idempotency_key: "corpus:observation",
      allow_write: true
    }),
    (previous) => repoCall("showcase_record_verdict", {
      run: runIdOf(previous[0]),
      item: itemIdOf(previous[0]),
      verdict: "pass",
      recorded_at: "2026-06-25T12:02:00.000Z",
      idempotency_key: "corpus:verdict",
      allow_write: true
    }),
    (previous) => repoCall("showcase_finish", {
      run: runIdOf(previous[0]),
      recorded_at: "2026-06-25T12:03:00.000Z",
      idempotency_key: "corpus:finish",
      allow_write: true
    }),
    (previous) => repoCall("showcase_request_approval", { run: runIdOf(previous[0]) })
  ]],
  ["showcase_verdict_without_observation", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("showcase_start", {
      select: "probe.core.alpha",
      generated_at: AT,
      recorded_at: AT,
      idempotency_key: "corpus:start",
      allow_write: true
    }),
    (previous) => repoCall("showcase_record_verdict", {
      run: runIdOf(previous[0]),
      item: itemIdOf(previous[0]),
      verdict: "pass",
      recorded_at: "2026-06-25T12:02:00.000Z",
      idempotency_key: "corpus:verdict",
      allow_write: true
    })
  ]],
  ["showcase_start_needs_a_plan", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("showcase_start", { allow_write: true })
  ]],
  ["showcase_start_unknown_selection", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("showcase_start", { select: "probe.core.nope", generated_at: AT, recorded_at: AT, allow_write: true })
  ]],
  ["showcase_start_plan_file_escape", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("showcase_start", { plan_file: "../escape.json", recorded_at: AT, allow_write: true })
  ]],
  ["showcase_decide_missing_arguments", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("showcase_decide", { run: "some-run", decision: "abort", allow_write: true })
  ]],
  ["showcase_observation_missing_arguments", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("showcase_record_observation", { run: "some-run", allow_write: true })
  ]],
  ["showcase_finish_missing_run", workspace, { UCM_MCP_WRITE: "1" }, [
    repoCall("showcase_finish", { allow_write: true })
  ]],

  // ---- the resources
  ["resource_matrix", workspace, {}, [request("resources/read", { uri: `uc://matrix?repo=${S}` })]],
  ["resource_matrix_status", workspace, {}, [request("resources/read", { uri: `uc://matrix/status?repo=${S}` })]],
  ["resource_freshness", workspace, {}, [request("resources/read", { uri: `uc://freshness?repo=${S}` })]],
  ["resource_bindings", workspace, {}, [request("resources/read", { uri: `uc://bindings?repo=${S}` })]],
  ["resource_ledger", workspace, {}, [request("resources/read", { uri: `uc://ledger?repo=${S}` })]],
  ["resource_evidence", workspace, {}, [request("resources/read", { uri: `uc://evidence?repo=${S}` })]],
  ["resource_config", workspace, {}, [request("resources/read", { uri: `uc://config?repo=${S}` })]],
  ["resource_schemas_index", bare, {}, [request("resources/read", { uri: "uc://schemas" })]],
  ["resource_one_schema_by_file_name", bare, {}, [
    request("resources/read", { uri: "uc://schemas/common.schema.json" })
  ]],
  ["resource_one_schema_by_short_name", bare, {}, [request("resources/read", { uri: "uc://schemas/common" })]],
  ["resource_unknown_schema", bare, {}, [request("resources/read", { uri: "uc://schemas/nope" })]],
  ["resource_unknown_uri", workspace, {}, [request("resources/read", { uri: "uc://not-a-resource" })]],
  ["resource_not_a_uc_uri", workspace, {}, [request("resources/read", { uri: "https://example.com" })]],
  ["resource_empty_uri", workspace, {}, [request("resources/read", { uri: "" })]],
  ["resource_repo_required", workspace, {}, [request("resources/read", { uri: "uc://matrix" })]],
  ["resource_repo_traversal", workspace, { UCM_MCP_REPO: "$SANDBOX" }, [
    request("resources/read", { uri: "uc://matrix?repo=../../etc" })
  ]],
  ["resource_configured_repo_default", workspace, { UCM_MCP_REPO: "$SANDBOX" }, [
    request("resources/read", { uri: "uc://matrix" })
  ]],
  ["resource_trailing_slash", workspace, {}, [request("resources/read", { uri: `uc://matrix/?repo=${S}` })]],

  // ---- the prompts
  ["prompt_adopt_repo", bare, {}, [request("prompts/get", { name: "uc/adopt-repo", arguments: { repo: "/tmp/repo" } })]],
  ["prompt_adopt_repo_without_argument", bare, {}, [request("prompts/get", { name: "uc/adopt-repo", arguments: {} })]],
  ["prompt_bind_row", bare, {}, [
    request("prompts/get", { name: "uc/bind-row", arguments: { row: "auth.login", file: "Sources/Auth.swift", repo: "/tmp/repo" } })
  ]],
  ["prompt_bind_row_minimal", bare, {}, [
    request("prompts/get", { name: "uc/bind-row", arguments: { row: "auth.login" } })
  ]],
  ["prompt_bind_row_missing_required", bare, {}, [
    request("prompts/get", { name: "uc/bind-row", arguments: { repo: "/tmp/repo" } })
  ]],
  ["prompt_bind_row_empty_required", bare, {}, [
    request("prompts/get", { name: "uc/bind-row", arguments: { row: "" } })
  ]],
  ["prompt_bind_row_non_string_argument", bare, {}, [
    request("prompts/get", { name: "uc/bind-row", arguments: { row: "auth.login", file: 7 } })
  ]],
  ["prompt_recover_row", bare, {}, [
    request("prompts/get", { name: "uc/recover-suspect-row", arguments: { row: "auth.login", repo: "/tmp/repo" } })
  ]],
  ["prompt_release_review", bare, {}, [
    request("prompts/get", { name: "uc/release-review", arguments: { repo: "/tmp/repo" } })
  ]],
  ["prompt_unknown", bare, {}, [request("prompts/get", { name: "uc/not-a-prompt", arguments: {} })]],
  ["prompt_missing_name", bare, {}, [request("prompts/get", {})]]
];

/** The run id a `showcase_start` response minted. */
function runIdOf(responseLine) {
  const envelope = envelopeOf(responseLine);
  return envelope.data.status.run_id;
}

/** The first plan item id of the run a `showcase_start` response minted. */
function itemIdOf(responseLine) {
  const envelope = envelopeOf(responseLine);
  return envelope.data.status.items[0].plan_item_id;
}

function envelopeOf(responseLine) {
  return JSON.parse(JSON.parse(responseLine).result.content[0].text);
}

/** One server process, one request/response round trip at a time. */
class Session {
  constructor(cwd, env) {
    this.child = spawn(process.execPath, [serverEntry], {
      cwd,
      env: { ...process.env, ...env },
      stdio: ["pipe", "pipe", "inherit"]
    });
    this.buffer = "";
    this.waiting = null;
    this.child.stdout.on("data", (chunk) => {
      this.buffer += chunk.toString();
      const index = this.buffer.indexOf("\n");
      if (index >= 0 && this.waiting) {
        const line = this.buffer.slice(0, index);
        this.buffer = this.buffer.slice(index + 1);
        const resolve = this.waiting;
        this.waiting = null;
        resolve(line);
      }
    });
  }

  /** The response line, or null when the server stayed silent for 300ms. */
  send(line) {
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        if (this.waiting) {
          this.waiting = null;
          resolve(null);
        }
      }, 300);
      this.waiting = (value) => {
        clearTimeout(timer);
        resolve(value);
      };
      this.child.stdin.write(`${line}\n`);
    });
  }

  stop() {
    this.child.kill();
  }
}

function writeFiles(directory, files) {
  for (const [path, contents] of Object.entries(files)) {
    const target = join(directory, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, contents);
  }
}

function escapeNonAscii(text) {
  return text.replace(/[-￿]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`);
}

const recorded = [];
for (const [name, files, environment, requests, options = {}] of cases) {
  const sandbox = realpathSync(mkdtempSync(join(tmpdir(), "uc-mcp-corpus-")));
  try {
    writeFiles(sandbox, files);
    const env = Object.fromEntries(
      Object.entries(environment).map(([key, value]) => [key, value.replaceAll(S, sandbox)])
    );
    const session = new Session(sandbox, env);
    const sentLines = [];
    const responseLines = [];
    try {
      for (const entry of requests) {
        const line = (typeof entry === "function" ? entry(responseLines) : entry).replaceAll(S, sandbox);
        sentLines.push(line);
        responseLines.push(await session.send(line));
      }
    } finally {
      session.stop();
    }

    const filesAfter = {};
    for (const path of options.filesAfter ?? []) {
      const target = join(sandbox, path);
      filesAfter[path] = existsFile(target) ? readFileSync(target, "utf8") : null;
    }

    const placeholder = (text) => (text === null ? null : text.replaceAll(sandbox, S));
    recorded.push({
      name,
      files,
      env: environment,
      requests: sentLines.map(placeholder),
      clock_fields: options.clockFields ?? [],
      responses: responseLines.map((line) => normalise(placeholder(line), options.clockFields ?? [])),
      files_after: Object.fromEntries(
        Object.entries(filesAfter).map(([path, contents]) => [path, normalise(placeholder(contents), options.clockFields ?? [])])
      ),
      workspace_listing: listing(sandbox).map((entry) => normalise(entry, []))
    });
  } finally {
    rmSync(sandbox, { recursive: true, force: true });
  }
}

function existsFile(path) {
  try {
    statSync(path);
    return true;
  } catch {
    return false;
  }
}

/** Every file left in the sandbox, so a read can be proved not to have written. */
function listing(directory) {
  const found = [];
  const walk = (current, prefix) => {
    for (const entry of readdirSync(current)) {
      const full = join(current, entry);
      if (statSync(full).isDirectory()) {
        walk(full, `${prefix}${entry}/`);
      } else {
        found.push(`${prefix}${entry}`);
      }
    }
  };
  walk(directory, "");
  return found.sort();
}

/** The genuinely nondeterministic values, and nothing else. */
function normalise(line, clockFields) {
  if (line === null) {
    return null;
  }
  let result = line;
  for (const field of ["jti", "iat", "exp", "generated_at", "evaluated_at", ...clockFields]) {
    const token = field === "jti" ? "$JTI" : field === "iat" ? "$IAT" : field === "exp" ? "$EXP" : "$NOW";
    result = result
      .replaceAll(new RegExp(`"${field}":"[^"]*"`, "g"), `"${field}":"${token}"`)
      .replaceAll(new RegExp(`\\\\"${field}\\\\":\\\\"[^\\\\"]*\\\\"`, "g"), `\\"${field}\\":\\"${token}\\"`);
  }
  return result
    .replaceAll(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g, "$UUID")
    .replaceAll(/by-id\/[0-9a-f]{2}\//g, "by-id/$SHARD/");
}

const json = escapeNonAscii(JSON.stringify({ cases: recorded }));
let pounds = "#";
while (json.includes(`"${pounds}`) || json.includes(`\\${pounds}`)) {
  pounds += "#";
}
const names = recorded.map((item) => `    "${item.name}",\n`).join("");
const swift = `// swiftlint:disable line_length single_line_closure_body
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript MCP server. DO NOT EDIT BY HAND.
//
// What node dist/uc-mcp.js answered for each request line, over real stdio.
//
// Regenerate with:
//   pnpm build
//   node UseCasesMCP/Scripts/generate-mcp-corpus.mjs
enum McpGoldenCorpus {
  static let caseNames: [String] = [
${names}  ]

  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable line_length single_line_closure_body
`;
mkdirSync(outputDirectory, { recursive: true });
const target = join(outputDirectory, "McpGoldenCorpus.swift");
writeFileSync(target, swift);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("McpGoldenCorpus.swift is not ASCII");
}
console.log(`wrote ${recorded.length} cases to ${target}`);
console.log(`relative to ${relative(repositoryRoot, target)}`);
