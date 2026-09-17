// Regenerates the CLI evidence-command corpus by running every case below
// through the REAL TypeScript CLI and recording exactly the bytes, exit codes
// and files it produced.
//
//   pnpm build
//   node UseCasesCLI/Scripts/generate-evidence-commands-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCLITests/Entry/EvidenceCommandsGoldenCorpus.swift
//     For each case: how its sandbox was set up (files), then its STEPS in
//     order — CLI runs, file writes, ledger appends and mode changes. Every CLI
//     run records its argv, stdout, stderr and exit status; after the last step
//     every file and directory the sandbox holds is recorded (file modes and
//     contents included). Covers row 4d: `evidence record` (self-reported and
//     `--perform` runs), `evidence status` and `evidence void`, golden, bad and
//     edge, in the JSON and human renderings.
//
// A sandbox is a temporary directory holding `demo-repo` (the workspace),
// `outside` and `home` (HOME for every run). Paths are recorded as
// placeholders: `$ROOT` for the temporary directory, `$SANDBOX` for
// `$ROOT/demo-repo`, `$CWD` for the directory the CLI ran in and `$REPO` for
// this repository.
//
// Every run gets exactly PATH and HOME — nothing else from this shell.
//
// Normalised HERE, because a later step's argv needs it: every evidence event
// id. `appendEvidenceEvent` mints a uuidv7 (the clock plus random bytes) and no
// flag pins it, yet `evidence void` must name one. Each id is replaced by
// `$EVENT<n>`, numbered in order of first appearance — in each run's stdout,
// then its stderr, then (after the last step) the tree's paths and contents in
// listing order — and the Swift test numbers its own ids the same way. The id
// is also the ledger's file name, so tree paths carry the placeholder too.
//
// Normalised by the Swift test on BOTH sides, never here: the millisecond ISO
// timestamps an append stamps (`recorded_at`, `captured_at`, and the
// `freshness_inputs.captured_at` replay derives from it). The envelope's own
// epoch `1970-01-01T00:00:00.000Z` is not masked.
//
// Everything else — intent digests, idempotency keys, output digests of a
// performed command, redacted summaries — is compared byte for byte, so no
// performed argv holds a sandbox path.
//
// Masked by the Swift test too: the message of an `evidence_parse_error`
// diagnostic, which is V8's own `JSON.parse` wording (the row 3 and 4b
// precedent in docs/rewrite/ladder-notes.md). Its code, its `source_path` and
// everything around it are compared.
//
// Recorded since row 4e: a performed command whose output PASSES `spawnSync`'s
// 1 MiB `maxBuffer` (`perform_output_past_the_buffer`). node keeps the 64 KiB
// read that crossed the limit — 1 MiB + 65,536 bytes — and the port now gives
// its socket pairs the same 64 KiB buffers, so the kept bytes and the output
// digest agree. Only a writer that fills the buffer faster than it is read can
// be recorded: `head -c … /dev/zero | tr` is one, and `/usr/bin/yes` is not
// (node's own kept bytes move run to run). The case beside it,
// `perform_large_output_under_the_buffer`, stays just under the limit.
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  statSync,
  appendFileSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const cliEntry = join(repositoryRoot, "packages/cli/dist/index.js");
const outputDirectory = join(packageRoot, "Tests/UseCasesCLITests/Entry");

const PORTED = [
  ["cli", "commands/evidence"],
  ["cli", "render"],
  ["cli", "runtime"],
  ["cli", "command/dispatch"],
  ["core", "evidence/appendEvidenceEvent"],
  ["core", "evidence/replayEvidence"],
  ["core", "evidence/jsonlLedger"],
  ["core", "evidence/assurance"]
];
for (const [pkg, name] of PORTED) {
  const source = statSync(join(repositoryRoot, `packages/${pkg}/src/${name}.ts`)).mtimeMs;
  const built = statSync(join(repositoryRoot, `packages/${pkg}/dist/${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`packages/${pkg}/dist/${name}.js is older than its source; run pnpm build first`);
  }
}

// ---------------------------------------------------------------------------
// Fixed material

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

function row(id) {
  return `  - id: ${id}
    title: Row ${id}
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so evidence can be recorded against it.
    preconditions: [Nothing.]
    trigger: An agent records evidence.
    scenarios:
      - id: ${id}.golden_runs
        kind: steps
        steps: [Record it.]
        observable_outcomes: [An event is appended.]
    observable_outcomes: [A JSONL event is appended under evidence.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`;
}

const shard = (featureId, ids) =>
  `schema_version: 1\nfeature:\n  id: ${featureId}\n  name: Probe\n  summary: Probe.\nuse_cases:\n${ids.map(row).join("")}`;

const MATRIX = shard("probe.core", ["probe.core.alpha", "probe.core.beta"]);

function workspace(extra = {}) {
  return {
    files: {
      "demo-repo/use-cases.yml": CONFIG,
      "demo-repo/use-cases/probe.yml": MATRIX,
      ...extra
    }
  };
}

const empty = { files: {} };
const unconfigured = { files: { "demo-repo/use-cases/probe.yml": MATRIX } };
const duplicated = workspace({ "demo-repo/use-cases/copy.yml": shard("probe.copy", ["probe.core.alpha"]) });
const brokenMatrix = workspace({ "demo-repo/use-cases/broken.yml": "schema_version: 1\nfeature:\n  id: probe.core\n" });

const S = "$SANDBOX";
const R = "$ROOT";

// Steps.
const uc = (args) => ({ kind: "uc", args });
const write = (path, content) => ({ kind: "write", path, content });
// Appends a line to the ledger of the evidence `$EVENTn` names, wherever the
// id puts it: `evidence/by-id/<first two code units>/<id>.jsonl`.
const appendLedger = (evidence, content) => ({ kind: "append_ledger", evidence, content });
const chmod = (path, mode) => ({ kind: "chmod", path, mode });

const repo = ["--repo", S];
const record = (...rest) => uc(["evidence", "record", ...repo, "--use-case", "probe.core.alpha", ...rest]);
const status = (...rest) => uc(["evidence", "status", ...repo, ...rest]);
const voidEvent = (evidence, head, ...rest) =>
  uc(["evidence", "void", ...repo, "--evidence", evidence, "--expected-head", head, "--reason", "superseded by a rerun", ...rest]);

// A hand-written void of `$EVENTn` at `sequence`, as a raw ledger line.
const voidLine = (evidence, id, sequence) =>
  `${JSON.stringify({
    schema_version: 1,
    event_type: "evidence_voided",
    event_id: id,
    aggregate_id: evidence,
    sequence,
    recorded_at: "2026-09-17T12:00:00.000Z",
    actor_type: "agent",
    host_surface: "codex.cli",
    idempotency_key: `hand:${id}`,
    intent_digest: `sha256:${"0".repeat(64)}`,
    target_event_id: evidence,
    reason: "hand written"
  })}\n`;

const SECRET_SUMMARY =
  "api_key=sk-abcdefghijklmnop token: ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAA key AKIAABCDEFGHIJKLMNOP password=hunter2 and sk-shortone";

const recordCases = [
  ["record_self_reported_json", workspace(), [record("--json")]],
  ["record_self_reported_text", workspace(), [record()]],
  ["record_kind_result_summary_json", workspace(), [record("--kind", "test_result", "--result", "pass", "--summary", "All green.", "--json")]],
  ["record_result_fail_text", workspace(), [record("--kind", "test_result", "--result", "fail", "--summary", "Red.")]],
  ["record_result_inconclusive_json", workspace(), [record("--result", "inconclusive", "--json")]],
  ["record_unknown_kind_and_result_are_unchecked", workspace(), [record("--kind", "bogus_kind", "--result", "bogus", "--json")]],
  ["record_explicit_idempotency_key", workspace(), [record("--idempotency-key", "my-key", "--json")]],
  ["record_idempotent_repeat_json", workspace(), [record("--json"), record("--json"), status("--json")]],
  ["record_idempotent_repeat_text", workspace(), [record(), record()]],
  ["record_idempotency_conflict_json", workspace(), [record("--idempotency-key", "k", "--summary", "one", "--json"), record("--idempotency-key", "k", "--summary", "two", "--json")]],
  ["record_idempotency_conflict_text", workspace(), [record("--idempotency-key", "k", "--summary", "one"), record("--idempotency-key", "k", "--summary", "two")]],
  ["record_two_rows_then_status", workspace(), [record("--json"), uc(["evidence", "record", ...repo, "--use-case", "probe.core.beta", "--result", "pass", "--json"]), status("--json"), status()]],
  ["record_secret_summary_redacted_json", workspace(), [record("--summary", SECRET_SUMMARY, "--json")]],
  ["record_secret_summary_redacted_text", workspace(), [record("--summary", SECRET_SUMMARY)]],
  ["record_redacted_summary_is_the_intent", workspace(), [record("--summary", "token=aaa", "--idempotency-key", "r", "--json"), record("--summary", "token=bbb", "--idempotency-key", "r", "--json")]],
  ["record_unicode_summary", workspace(), [record("--summary", "Café — 🚀 \"quoted\"\nsecond line", "--json")]],
  ["record_empty_summary_uses_default", workspace(), [record("--summary", "", "--json")]],
  ["record_empty_kind_is_kept", workspace(), [record("--kind", "", "--json")]],
  ["record_missing_use_case_json", workspace(), [uc(["evidence", "record", ...repo, "--json"])]],
  ["record_missing_use_case_text", workspace(), [uc(["evidence", "record", ...repo])]],
  ["record_empty_use_case", workspace(), [uc(["evidence", "record", ...repo, "--use-case", "", "--json"])]],
  ["record_unknown_use_case_json", workspace(), [uc(["evidence", "record", ...repo, "--use-case", "probe.core.nope", "--json"])]],
  ["record_unknown_use_case_text", workspace(), [uc(["evidence", "record", ...repo, "--use-case", "probe.core.nope"])]],
  ["record_ambiguous_use_case", duplicated, [record("--json")]],
  ["record_incomplete_matrix_still_resolves", brokenMatrix, [record("--json")]],
  ["record_unconfigured_workspace", unconfigured, [record("--json")]],
  ["record_empty_workspace", empty, [record("--json")]],
  ["record_missing_repo_json", empty, [uc(["evidence", "record", "--repo", `${S}/missing`, "--use-case", "probe.core.alpha", "--json"])]],
  ["record_missing_repo_text", empty, [uc(["evidence", "record", "--repo", `${S}/missing`, "--use-case", "probe.core.alpha"])]],
  ["record_data_root_escape", workspace(), [record("--data-root", `${R}/outside`, "--json")]],
  ["record_component_unknown", workspace(), [record("--component", "other", "--json")]],
  ["record_unknown_flag", workspace(), [record("--summery", "x", "--json")]],
  ["record_flag_value_swallows_next_flag", workspace(), [uc(["evidence", "record", ...repo, "--use-case", "--json"])]],
  ["record_damaged_ledger_refused_json", workspace({ "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "not json\n" }), [record("--json")]],
  ["record_damaged_ledger_refused_text", workspace({ "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "{\"schema_version\":1}\n" }), [record()]],
  ["record_lock_directory_unwritable_json", workspace({ "demo-repo/evidence/.locks/.keep": "" }), [chmod("demo-repo/evidence/.locks", 0o555), record("--json"), chmod("demo-repo/evidence/.locks", 0o755)]],
  ["record_evidence_directory_is_a_file", workspace({ "demo-repo/evidence": "not a directory\n" }), [record("--json")]],
  ["record_leaves_the_lock_directory", workspace(), [record("--json"), status("--json")]]
];

const perform = (...rest) => record("--perform", ...rest);
const performCases = [
  ["perform_pass_json", workspace(), [perform("--json", "--", "/bin/echo", "hello")]],
  ["perform_pass_text", workspace(), [perform("--", "/bin/echo", "hello")]],
  ["perform_fail_exit_code_json", workspace(), [perform("--json", "--", "/bin/sh", "-c", "printf out; printf err >&2; exit 3")]],
  ["perform_fail_exit_code_text", workspace(), [perform("--", "/bin/sh", "-c", "exit 3")]],
  ["perform_searches_path", workspace(), [perform("--json", "--", "true")]],
  ["perform_runs_in_workspace_root", workspace(), [perform("--json", "--", "/bin/ls", "use-cases")]],
  ["perform_missing_executable_json", workspace(), [perform("--json", "--", "/nonexistent/tool", "arg")]],
  ["perform_unknown_command_on_path", workspace(), [perform("--json", "--", "uc-definitely-not-a-command")]],
  ["perform_killed_by_signal", workspace(), [perform("--json", "--", "/bin/sh", "-c", "kill -TERM $$")]],
  ["perform_invalid_utf8_output", workspace(), [perform("--json", "--", "/bin/sh", "-c", "printf '\\377\\376ok'")]],
  ["perform_large_output_under_the_buffer", workspace(), [perform("--json", "--", "/bin/sh", "-c", "head -c 1000000 /dev/zero | tr '\\000' a")]],
  ["perform_output_past_the_buffer", workspace(), [perform("--json", "--", "/bin/sh", "-c", "head -c 1200000 /dev/zero | tr '\\000' a")]],
  ["perform_explicit_kind_result_summary", workspace(), [perform("--kind", "test_result", "--result", "pass", "--summary", "Mine.", "--json", "--", "/bin/sh", "-c", "exit 1")]],
  ["perform_secret_in_argv_is_kept", workspace(), [perform("--json", "--", "/bin/echo", "token=abc123secret")]],
  ["perform_idempotent_repeat", workspace(), [perform("--json", "--", "/bin/echo", "same"), perform("--json", "--", "/bin/echo", "same")]],
  ["perform_changed_output_is_a_new_record", workspace(), [perform("--json", "--", "/bin/echo", "one"), perform("--json", "--", "/bin/echo", "two"), status("--json")]],
  ["perform_flags_after_separator_are_argv", workspace(), [perform("--", "/bin/echo", "--json", "--summary", "x")]],
  ["perform_flags_between_perform_and_separator", workspace(), [record("--perform", "--result", "pass", "--json", "--", "/bin/echo", "x")]],
  ["perform_without_command_json", workspace(), [perform("--json")]],
  ["perform_without_command_text", workspace(), [perform()]],
  ["perform_separator_with_nothing_after", workspace(), [perform("--json", "--")]],
  ["separator_without_perform_is_ignored", workspace(), [record("--json", "--", "/bin/echo", "hi")]],
  ["perform_unresolved_use_case_does_not_run", workspace(), [uc(["evidence", "record", ...repo, "--use-case", "probe.core.nope", "--perform", "--json", "--", "/usr/bin/touch", "ran"])]],
  ["perform_then_status_text", workspace(), [perform("--json", "--", "/bin/echo", "hello"), record("--json"), status()]]
];

const statusCases = [
  ["status_empty_json", workspace(), [status("--json")]],
  ["status_empty_text", workspace(), [status()]],
  ["status_after_record_text", workspace(), [record("--json"), status()]],
  ["status_damaged_json", workspace({ "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "not json\n" }), [status("--json")]],
  ["status_damaged_text", workspace({ "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "{\"schema_version\":1}\n" }), [status()]],
  ["status_torn_tail", workspace(), [record("--json"), appendLedger("$EVENT1", "{\"schema_version\":1,\"event_t"), status("--json"), status()]],
  ["status_sequence_conflict", workspace(), [record("--json"), appendLedger("$EVENT1", voidLine("$EVENT1", "hand-void-one", 2)), appendLedger("$EVENT1", voidLine("$EVENT1", "hand-void-two", 2)), status("--json"), status()]],
  ["status_damage_blocks_record_and_void", workspace(), [record("--json"), appendLedger("$EVENT1", "not json\n"), record("--summary", "later", "--json"), voidEvent("$EVENT1", "$EVENT1", "--json")]],
  ["status_unconfigured_workspace", unconfigured, [status("--json")]],
  ["status_missing_repo_json", empty, [uc(["evidence", "status", "--repo", `${S}/missing`, "--json"])]],
  ["status_missing_repo_text", empty, [uc(["evidence", "status", "--repo", `${S}/missing`])]],
  ["status_data_root_escape", workspace(), [status("--data-root", R, "--json")]],
  ["status_unknown_flag", workspace(), [status("--use-case", "probe.core.alpha", "--bogus", "--json")]],
  ["status_evidence_directory_is_a_file", workspace({ "demo-repo/evidence": "not a directory\n" }), [status("--json")]]
];

const voidCases = [
  ["void_json", workspace(), [record("--json"), voidEvent("$EVENT1", "$EVENT1", "--json"), status("--json")]],
  ["void_text", workspace(), [record("--json"), voidEvent("$EVENT1", "$EVENT1"), status()]],
  ["void_twice_is_an_invalid_transition_json", workspace(), [record("--json"), voidEvent("$EVENT1", "$EVENT1", "--json"), voidEvent("$EVENT1", "$EVENT1", "--json")]],
  ["void_twice_is_an_invalid_transition_text", workspace(), [record("--json"), voidEvent("$EVENT1", "$EVENT1"), voidEvent("$EVENT1", "$EVENT1")]],
  ["void_with_new_key_after_void", workspace(), [record("--json"), voidEvent("$EVENT1", "$EVENT1", "--json"), voidEvent("$EVENT1", "$EVENT2", "--idempotency-key", "again", "--json")]],
  ["void_stale_head_json", workspace(), [record("--json"), record("--summary", "other", "--idempotency-key", "other", "--json"), voidEvent("$EVENT1", "$EVENT2", "--json")]],
  ["void_stale_head_text", workspace(), [record("--json"), record("--summary", "other", "--idempotency-key", "other", "--json"), voidEvent("$EVENT1", "$EVENT2")]],
  ["void_unknown_evidence_json", workspace(), [voidEvent("probe.evidence.missing", "probe.evidence.missing", "--json")]],
  ["void_unknown_evidence_text", workspace(), [voidEvent("probe.evidence.missing", "whatever")]],
  ["void_invalid_id_uppercase", workspace(), [voidEvent("Probe.Evidence", "x", "--json")]],
  ["void_invalid_id_traversal_json", workspace(), [voidEvent("../outside", "x", "--json")]],
  ["void_invalid_id_traversal_text", workspace(), [voidEvent("../outside", "x")]],
  ["void_invalid_id_empty_segment", workspace(), [voidEvent("a..b", "x", "--json")]],
  ["void_missing_reason_json", workspace(), [uc(["evidence", "void", ...repo, "--evidence", "a", "--expected-head", "a", "--json"])]],
  ["void_missing_reason_text", workspace(), [uc(["evidence", "void", ...repo, "--evidence", "a", "--expected-head", "a"])]],
  ["void_empty_reason", workspace(), [uc(["evidence", "void", ...repo, "--evidence", "a", "--expected-head", "a", "--reason", "", "--json"])]],
  ["void_missing_head", workspace(), [uc(["evidence", "void", ...repo, "--evidence", "a", "--reason", "r", "--json"])]],
  ["void_missing_everything", workspace(), [uc(["evidence", "void", ...repo, "--json"])]],
  ["void_missing_arguments_before_invalid_id", workspace(), [uc(["evidence", "void", ...repo, "--evidence", "BAD", "--json"])]],
  ["void_explicit_idempotency_key", workspace(), [record("--json"), voidEvent("$EVENT1", "$EVENT1", "--idempotency-key", "void-key", "--json")]],
  ["void_idempotency_conflict", workspace(), [record("--idempotency-key", "shared", "--json"), voidEvent("$EVENT1", "$EVENT1", "--idempotency-key", "shared", "--json")]],
  ["void_reason_secret_is_not_redacted", workspace(), [record("--json"), uc(["evidence", "void", ...repo, "--evidence", "$EVENT1", "--expected-head", "$EVENT1", "--reason", "token=abc123 sk-abcdefghijklmnop", "--json"])]],
  ["void_damaged_ledger_json", workspace({ "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "not json\n" }), [voidEvent("probe.evidence.missing", "x", "--json")]],
  ["void_damaged_ledger_text", workspace({ "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "not json\n" }), [voidEvent("probe.evidence.missing", "x")]],
  ["void_lock_directory_unwritable", workspace({ "demo-repo/evidence/.locks/.keep": "" }), [chmod("demo-repo/evidence/.locks", 0o555), voidEvent("probe.evidence.missing", "x", "--json"), chmod("demo-repo/evidence/.locks", 0o755)]],
  ["void_evidence_directory_is_a_file", workspace({ "demo-repo/evidence": "not a directory\n" }), [voidEvent("probe.evidence.missing", "x", "--json")]],
  ["void_missing_repo", empty, [uc(["evidence", "void", "--repo", `${S}/missing`, "--evidence", "a", "--expected-head", "a", "--reason", "r", "--json"])]],
  ["void_missing_repo_before_arguments", empty, [uc(["evidence", "void", "--repo", `${S}/missing`, "--json"])]],
  ["void_data_root_escape", workspace(), [voidEvent("a", "a", "--data-root", `${R}/outside`, "--json")]],
  ["void_unknown_flag", workspace(), [voidEvent("a", "a", "--why", "x", "--json")]],
  ["void_performed_run", workspace(), [perform("--json", "--", "/bin/echo", "hello"), voidEvent("$EVENT1", "$EVENT1", "--json"), status()]]
];

const cases = [...recordCases, ...performCases, ...statusCases, ...voidCases];

// ---------------------------------------------------------------------------
// Running

function escapeNonAscii(text) {
  return text.replace(/[^\x00-\x7f]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`);
}

function tree(root) {
  const entries = [];
  const walk = (relative) => {
    const absolute = relative ? join(root, relative) : root;
    for (const name of readdirSync(absolute)) {
      if (name === ".git") continue;
      const path = relative ? `${relative}/${name}` : name;
      const full = join(root, path);
      const stat = lstatSync(full);
      if (stat.isSymbolicLink()) {
        entries.push({ path, kind: "symlink", target: readlinkSync(full) });
      } else if (stat.isDirectory()) {
        entries.push({ path, kind: "directory" });
        walk(path);
      } else {
        entries.push({ path, kind: "file", mode: (stat.mode & 0o777).toString(8), content: readFileSync(full, "utf8") });
      }
    }
  };
  walk("");
  return entries.sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));
}

// A uuidv7 as `uuidv7()` in appendEvidenceEvent.ts writes one.
const EVENT_ID = /[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}/g;

const names = new Set();
const recorded = [];
for (const [name, setup, steps] of cases) {
  if (names.has(name)) throw new Error(`duplicate case ${name}`);
  names.add(name);
  const root = realpathSync(mkdtempSync(join(tmpdir(), "uc-evidence-")));
  const sandbox = join(root, "demo-repo");
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "uc-evidence-cwd-")));
  const events = new Map();
  const numbered = (text) =>
    text.replace(EVENT_ID, (id) => {
      if (!events.has(id)) events.set(id, `$EVENT${events.size + 1}`);
      return events.get(id);
    });
  const placeholders = (text) =>
    numbered(text.split(sandbox).join("$SANDBOX").split(root).join("$ROOT").split(cwd).join("$CWD").split(repositoryRoot).join("$REPO"));
  const concrete = (text) => {
    let result = text.split("$SANDBOX").join(sandbox).split("$ROOT").join(root).split("$CWD").join(cwd).split("$REPO").join(repositoryRoot);
    for (const [id, placeholder] of [...events.entries()].reverse()) result = result.split(placeholder).join(id);
    if (/\$EVENT[0-9]/.test(result)) throw new Error(`${name}: unbound placeholder in ${text}`);
    return result;
  };
  const environment = { PATH: process.env.PATH, HOME: join(root, "home") };
  try {
    mkdirSync(join(root, "outside"));
    mkdirSync(join(root, "home"));
    mkdirSync(sandbox);
    for (const [path, content] of Object.entries(setup.files)) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), content);
    }
    const runs = [];
    for (const step of steps) {
      if (step.kind === "uc") {
        const result = spawnSync(process.execPath, [cliEntry, ...step.args.map(concrete)], { cwd, encoding: "utf8", env: environment });
        runs.push({ stdout: placeholders(result.stdout), stderr: placeholders(result.stderr), status: result.status });
      } else if (step.kind === "write") {
        mkdirSync(dirname(join(root, step.path)), { recursive: true });
        writeFileSync(join(root, step.path), step.content);
      } else if (step.kind === "append_ledger") {
        const id = concrete(step.evidence);
        appendFileSync(join(sandbox, "evidence", "by-id", id.slice(0, 2), `${id}.jsonl`), concrete(step.content));
      } else if (step.kind === "chmod") {
        chmodSync(join(root, step.path), step.mode);
      } else {
        throw new Error(`${name}: unknown step ${step.kind}`);
      }
    }
    const after = tree(root).map((entry) => {
      const path = placeholders(entry.path);
      return entry.kind !== "file" ? { ...entry, path } : { ...entry, path, content: placeholders(entry.content) };
    });
    recorded.push({
      name,
      setup: { files: Object.entries(setup.files).map(([path, content]) => ({ path, content })) },
      steps,
      runs,
      tree_after: after.sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0))
    });
  } finally {
    try {
      chmodSync(join(sandbox, "evidence", ".locks"), 0o755);
    } catch {
      // No lock directory in this case.
    }
    rmSync(root, { recursive: true, force: true });
    rmSync(cwd, { recursive: true, force: true });
  }
}

const json = escapeNonAscii(JSON.stringify({ cases: recorded }));
let pounds = "#";
while (json.includes(`"${pounds}`) || json.includes(`\\${pounds}`)) {
  pounds += "#";
}
const caseNames = recorded.map((item) => `    "${item.name}",\n`).join("");
const swift = `// swiftlint:disable line_length single_line_closure_body
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript CLI. DO NOT EDIT BY HAND.
//
// What node packages/cli/dist/index.js wrote, returned and left on disk for
// each step of each evidence-command case.
//
// Regenerate with:
//   pnpm build
//   node UseCasesCLI/Scripts/generate-evidence-commands-corpus.mjs
enum EvidenceCommandsGoldenCorpus {
  static let caseNames: [String] = [
${caseNames}  ]

  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable line_length single_line_closure_body
`;
mkdirSync(outputDirectory, { recursive: true });
const target = join(outputDirectory, "EvidenceCommandsGoldenCorpus.swift");
writeFileSync(target, swift);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("EvidenceCommandsGoldenCorpus.swift is not ASCII");
}
console.log(`wrote ${recorded.length} cases to ${target}`);
