// Regenerates `Tests/UseCasesCoreTests/Evidence/EvidenceGoldenCorpus.swift` by
// running every case below through the REAL TypeScript in
// `packages/core/dist/evidence` and `packages/core/dist/errors`, against REAL
// temporary directories, and recording exactly what it returns and writes.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-evidence-corpus.mjs
//
// The TypeScript is the oracle (ADR 0007 decision 8). The script refuses to
// run against a `dist` older than its `src`.
//
// Nondeterminism is isolated the way the Swift side injects it: `Date` (both
// `Date.now()` and `new Date()`) reads a clock this script sets per step, and
// `crypto.randomBytes` returns the bytes this script sets per step, patched
// into the live ESM binding with `syncBuiltinESMExports` BEFORE the core is
// imported. Everything else runs unmodified.
//
// Ledger lines are carried as TEXT so their key order is exactly what the code
// under test reads, and the corpus is emitted ASCII-only. Absolute paths are
// replaced by `<workspace>`.
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
import { createRequire, syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const coreRoot = join(repositoryRoot, "packages/core");
const testsDirectory = join(packageRoot, "Tests/UseCasesCoreTests/Evidence");

const PORTED = [
  "errors",
  "durableWrite",
  "errors/registry",
  "errors/render",
  "evidence/types",
  "evidence/assurance",
  "evidence/results",
  "evidence/performedRuns",
  "evidence/linkEvidence",
  "evidence/jsonlLedger",
  "evidence/replayEvidence",
  "evidence/appendEvidenceEvent"
];

for (const name of PORTED) {
  const source = statSync(join(coreRoot, "src", `${name}.ts`)).mtimeMs;
  const built = statSync(join(coreRoot, "dist", `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/${name}.js is older than src; rebuild packages/core first`);
  }
}

// ---------------------------------------------------------------------------
// Isolated nondeterminism: installed before the core is imported
// ---------------------------------------------------------------------------

const RealDate = Date;
let clockMilliseconds = null;
let clockStep = 0;
function now() {
  if (clockMilliseconds === null) {
    return RealDate.now();
  }
  const value = clockMilliseconds;
  clockMilliseconds += clockStep;
  return value;
}
class ControlledDate extends RealDate {
  constructor(...args) {
    if (args.length === 0) {
      super(now());
    } else {
      super(...args);
    }
  }
  static now() {
    return now();
  }
}
globalThis.Date = ControlledDate;

const require = createRequire(import.meta.url);
const nodeCrypto = require("node:crypto");
const realRandomBytes = nodeCrypto.randomBytes;
let randomHex = null;
nodeCrypto.randomBytes = (size, callback) => {
  if (randomHex === null || callback !== undefined) {
    return realRandomBytes(size, callback);
  }
  const bytes = Buffer.from(randomHex, "hex");
  if (bytes.length !== size) {
    throw new Error(`fixed random source holds ${bytes.length} bytes, ${size} requested`);
  }
  return bytes;
};
syncBuiltinESMExports();

const core = await import(join(coreRoot, "dist/index.js"));
const registryModule = await import(join(coreRoot, "dist/errors/registry.js"));
const renderModule = await import(join(coreRoot, "dist/errors/render.js"));
const {
  appendEvidenceEvent,
  appendEvidenceVoidEvent,
  collectPerformedRuns,
  deriveEvidenceAssurance,
  evaluateEvidenceFreshness,
  linkEvidenceToMatrix,
  loadUseCaseMatrix,
  readEvidenceLedgers,
  replayEvidence,
  resolveWorkspaceContext,
  toEvidenceAppendResult,
  toEvidenceStatusResult
} = core;

// ---------------------------------------------------------------------------
// Trees on disk
// ---------------------------------------------------------------------------

const file = (path, text) => ({ kind: "file", path, text });
const bytesFile = (path, bytes) => ({ kind: "file", path, base64: Buffer.from(bytes).toString("base64") });
const directory = (path) => ({ kind: "directory", path });
const symlink = (path, target) => ({ kind: "symlink", path, target });
const mode = (path, octal) => ({ kind: "mode", path, mode: octal });

function buildTree(tree) {
  const workspace = realpathSync(mkdtempSync(join(tmpdir(), "evidence-corpus-")));
  for (const entry of tree) {
    const target = join(workspace, entry.path);
    if (entry.kind !== "mode") {
      mkdirSync(dirname(target), { recursive: true });
    }
    switch (entry.kind) {
      case "file":
        writeFileSync(target, entry.base64 !== undefined ? Buffer.from(entry.base64, "base64") : entry.text);
        break;
      case "directory":
        mkdirSync(target, { recursive: true });
        break;
      case "symlink":
        symlinkSync(entry.target, target);
        break;
      case "mode":
        chmodSync(target, entry.mode);
        break;
      default:
        throw new Error(`unknown tree entry ${entry.kind}`);
    }
  }
  return workspace;
}

function restoreModes(workspace, tree) {
  for (const entry of [...tree].reverse()) {
    if (entry.kind === "mode") {
      chmodSync(join(workspace, entry.path), 0o755);
    }
  }
}

function removeTree(workspace, tree) {
  restoreModes(workspace, tree);
  rmSync(workspace, { recursive: true, force: true });
}

function tokenized(value, workspace) {
  if (value === undefined) {
    return undefined;
  }
  return JSON.parse(JSON.stringify(value).split(workspace).join("<workspace>"));
}

function listTree(root, current = root) {
  const out = [];
  for (const name of readdirSync(current).sort()) {
    const full = join(current, name);
    const stat = lstatSync(full);
    const path = relative(root, full);
    if (stat.isDirectory()) {
      out.push({ path: `${path}/` });
      out.push(...listTree(root, full));
    } else if (stat.isSymbolicLink()) {
      out.push({ path });
    } else {
      out.push({ path, text: readFileSync(full, "utf8") });
    }
  }
  return out;
}

function thrown(error) {
  return { code: error.code ?? null, message: error.message, name: error.constructor.name };
}

// ---------------------------------------------------------------------------
// Ledger lines
// ---------------------------------------------------------------------------

const ZERO_HASH = `sha256:${"0".repeat(64)}`;
const HASH_A = `sha256:${"a".repeat(64)}`;
const HASH_B = `sha256:${"b".repeat(64)}`;

const lines = (...items) => items.map((item) => (typeof item === "string" ? item : JSON.stringify(item))).join("\n") + "\n";

function recorded(id, extra = {}, payload = {}) {
  return {
    schema_version: 1,
    event_type: "evidence_recorded",
    event_id: `${id}-e1`,
    aggregate_id: id,
    sequence: 1,
    recorded_at: "2026-01-02T03:04:05.678Z",
    actor_type: "agent",
    host_surface: "codex.cli",
    idempotency_key: `key-${id}`,
    payload: {
      targets: [{ use_case_id: "fixture.row", use_case_semantic_hash: HASH_A }],
      kind: "manual_observation",
      captured_at: "2026-01-02T03:04:05.678Z",
      result: "pass",
      summary: `Observed ${id}.`,
      producer: { type: "agent" },
      method: { type: "reported" },
      ...payload
    },
    ...extra
  };
}

function follow(id, sequence, eventType, targetEventId, extra = {}) {
  return {
    schema_version: 1,
    event_type: eventType,
    event_id: `${id}-e${sequence}`,
    aggregate_id: id,
    sequence,
    recorded_at: "2026-01-03T00:00:00.000Z",
    actor_type: "user",
    host_surface: "claude.cli",
    idempotency_key: `key-${id}-${sequence}`,
    target_event_id: targetEventId,
    ...extra
  };
}

const ledger = (id, ...events) => file(`evidence/by-id/${id.slice(0, 2)}/${id}.jsonl`, lines(...events));

// ---------------------------------------------------------------------------
// Reading and replaying ledgers
// ---------------------------------------------------------------------------

function contextFor(workspace) {
  return resolveWorkspaceContext({ workspaceRoot: workspace });
}

function snapshotRecord(snapshot) {
  return {
    status_result: toEvidenceStatusResult(snapshot),
    complete: snapshot.complete,
    integrity: snapshot.integrity,
    ledgers: snapshot.ledgers,
    aggregates: snapshot.aggregates,
    diagnostics: snapshot.diagnostics,
    counts: snapshot.counts,
    events: snapshot.events
  };
}

function runRead(testCase) {
  const workspace = buildTree(testCase.tree);
  try {
    const context = contextFor(workspace);
    let read;
    try {
      read = { read: readEvidenceLedgers(context) };
    } catch (error) {
      read = { read_throws: thrown(error) };
    }
    let replay;
    try {
      replay = { replay: snapshotRecord(replayEvidence({ context })) };
    } catch (error) {
      replay = { replay_throws: thrown(error) };
    }
    return tokenized({ name: testCase.name, tree: testCase.tree, ...read, ...replay }, workspace);
  } finally {
    removeTree(workspace, testCase.tree);
  }
}

const readCases = [
  { name: "no_evidence_directory", tree: [file("README.md", "nothing\n")] },
  { name: "empty_evidence_directory", tree: [directory("evidence")] },
  { name: "one_clean_ledger", tree: [ledger("ev-one", recorded("ev-one"))] },
  {
    name: "blank_and_whitespace_lines_are_skipped",
    tree: [file("evidence/by-id/ev/ev-blank.jsonl", `\n   \n${JSON.stringify(recorded("ev-blank"))}\n\t\n\n`)]
  },
  {
    name: "crlf_line_endings",
    tree: [file("evidence/by-id/ev/ev-crlf.jsonl", `${JSON.stringify(recorded("ev-crlf"))}\r\n\r\n`)]
  },
  {
    name: "lone_carriage_return_is_not_a_line_break",
    tree: [file("evidence/by-id/ev/ev-cr.jsonl", `${JSON.stringify(recorded("ev-cr"))}\r${JSON.stringify(recorded("ev-cr2"))}\n`)]
  },
  {
    name: "torn_tail",
    tree: [file("evidence/by-id/ev/ev-torn.jsonl", `${JSON.stringify(recorded("ev-torn"))}\n{"schema_version":1,"event_ty`)]
  },
  {
    name: "unterminated_but_complete_final_line_is_torn",
    tree: [file("evidence/by-id/ev/ev-unterminated.jsonl", JSON.stringify(recorded("ev-unterminated")))]
  },
  {
    name: "whitespace_only_unterminated_tail_is_not_torn",
    tree: [file("evidence/by-id/ev/ev-space.jsonl", `${JSON.stringify(recorded("ev-space"))}\n   `)]
  },
  { name: "empty_ledger_file", tree: [file("evidence/by-id/ev/ev-empty.jsonl", "")] },
  {
    name: "parse_errors_and_foreign_lines",
    tree: [
      file(
        "evidence/by-id/ev/ev-mixed.jsonl",
        lines(
          "{not json",
          JSON.stringify(recorded("ev-mixed")),
          "[1,2,3]",
          "null",
          "42",
          '"text"',
          '{"event_type":"evidence_recorded","event_id":"x","aggregate_id":"y","sequence":"1"}',
          '{"event_type":"evidence_recorded","event_id":"x","sequence":1}',
          " {}",
          "{} trailing"
        )
      )
    ]
  },
  {
    name: "duplicate_keys",
    tree: [
      file(
        "evidence/by-id/ev/ev-dups.jsonl",
        lines(
          '{"a":1,"a":2}',
          '{"a":{"b":1},"c":{"b":2}}',
          '{"outer":{"x":1,"x":2}}',
          '{"a\\"b":1,"a\\\\b":2}',
          '{"k" :1, "k"\t: 2}',
          '["a","a"]',
          '{"s":"{\\"a\\":1,\\"a\\":2}"}',
          '{"a":1}{"a":2}',
          JSON.stringify(recorded("ev-dups"))
        )
      )
    ]
  },
  {
    name: "invalid_utf8_throws",
    tree: [
      ledger("ev-good", recorded("ev-good")),
      bytesFile("evidence/by-id/ev/ev-bad.jsonl", [0x7b, 0x22, 0xff, 0xfe, 0x22, 0x7d, 0x0a])
    ]
  },
  {
    name: "byte_order_mark_is_stripped",
    tree: [bytesFile("evidence/by-id/ev/ev-bom.jsonl", [0xef, 0xbb, 0xbf, ...Buffer.from(`${JSON.stringify(recorded("ev-bom"))}\n`)])]
  },
  {
    name: "symlinked_ledgers_and_directories_are_skipped",
    tree: [
      ledger("ev-real", recorded("ev-real")),
      file("outside/ev-outside.jsonl", lines(recorded("ev-outside"))),
      symlink("evidence/by-id/ev/ev-link.jsonl", "ev-real.jsonl"),
      symlink("evidence/by-id/ev/ev-out.jsonl", "../../../outside/ev-outside.jsonl"),
      symlink("evidence/linked-dir", "../outside"),
      symlink("evidence/dangling.jsonl", "nowhere.jsonl")
    ]
  },
  {
    name: "evidence_root_itself_a_symlink_is_followed",
    tree: [file("real-evidence/by-id/ev/ev-root.jsonl", lines(recorded("ev-root"))), symlink("evidence", "real-evidence")]
  },
  {
    name: "evidence_root_is_a_file",
    tree: [file("evidence", "not a directory\n")]
  },
  {
    name: "only_dot_jsonl_regular_files",
    tree: [
      file("evidence/a.JSONL", lines(recorded("ev-upper"))),
      file("evidence/b.jsonl.bak", lines(recorded("ev-bak"))),
      file("evidence/.jsonl", lines(recorded("ev-dotfile"))),
      file("evidence/c.json", lines(recorded("ev-json"))),
      file("evidence/folder.jsonl/inner.jsonl", lines(recorded("ev-inner"))),
      file("evidence/notes.txt", "notes\n")
    ]
  },
  {
    name: "walk_is_locale_but_final_order_is_code_unit",
    tree: ["a", "B", "_x", "-x", "a-b", "a_b", "a.b", "a0", "ab", "é", "e", "Z/inner", "z/inner"].map((name, index) =>
      file(`evidence/${name}.jsonl`, lines(recorded(`ev-order-${String(index).padStart(2, "0")}`)))
    )
  },
  {
    name: "unreadable_ledger_throws",
    tree: [ledger("ev-locked", recorded("ev-locked")), mode("evidence/by-id/ev/ev-locked.jsonl", 0o000)]
  },
  // --- replay --------------------------------------------------------------
  {
    name: "duplicate_identical_event_across_files",
    tree: [file("evidence/one.jsonl", lines(recorded("ev-dup"))), file("evidence/two.jsonl", lines(recorded("ev-dup")))]
  },
  {
    name: "duplicate_identical_event_with_reordered_keys",
    tree: [
      file("evidence/one.jsonl", lines(recorded("ev-dup"))),
      file("evidence/two.jsonl", lines(Object.fromEntries(Object.entries(recorded("ev-dup")).reverse())))
    ]
  },
  {
    name: "conflicting_duplicate_event_id",
    tree: [
      file("evidence/one.jsonl", lines(recorded("ev-conflict"))),
      file("evidence/two.jsonl", lines(recorded("ev-conflict", {}, { summary: "Different." })))
    ]
  },
  {
    name: "conflicting_duplicate_event_id_across_aggregates",
    tree: [
      file("evidence/one.jsonl", lines(recorded("ev-first"), recorded("ev-other"))),
      file("evidence/two.jsonl", lines({ ...recorded("ev-second"), event_id: "ev-first-e1" }))
    ]
  },
  {
    name: "sequence_conflict",
    tree: [ledger("ev-seq", recorded("ev-seq"), { ...recorded("ev-seq"), event_id: "ev-seq-other" })]
  },
  {
    name: "sequence_gap",
    tree: [ledger("ev-gap", recorded("ev-gap"), follow("ev-gap", 3, "evidence_voided", "ev-gap-e1"))]
  },
  {
    name: "sequence_not_starting_at_one",
    tree: [ledger("ev-zero", { ...recorded("ev-zero"), sequence: 0 })]
  },
  {
    name: "fractional_and_negative_zero_sequences",
    tree: [
      ledger("ev-frac", { ...recorded("ev-frac"), sequence: 1.5 }),
      file("evidence/by-id/ev/ev-negzero.jsonl", `${JSON.stringify(recorded("ev-negzero")).replace('"sequence":1', '"sequence":-0')}\n`),
      file("evidence/by-id/ev/ev-float.jsonl", `${JSON.stringify(recorded("ev-float")).replace('"sequence":1', '"sequence":1.0')}\n`)
    ]
  },
  {
    name: "no_initial_recorded_event",
    tree: [ledger("ev-noinit", { ...follow("ev-noinit", 1, "evidence_voided", "nothing") })]
  },
  {
    name: "two_recorded_events",
    tree: [ledger("ev-tworec", recorded("ev-tworec"), { ...recorded("ev-tworec"), event_id: "ev-tworec-e2", sequence: 2 })]
  },
  {
    name: "event_must_target_head",
    tree: [ledger("ev-target", recorded("ev-target"), follow("ev-target", 2, "evidence_voided", "wrong-head"))]
  },
  {
    name: "correction_then_void",
    tree: [
      ledger(
        "ev-corr",
        recorded("ev-corr"),
        follow("ev-corr", 2, "evidence_corrected", "ev-corr-e1", {
          replacement: {
            targets: [{ use_case_id: "fixture.row", scenario_id: "golden", use_case_semantic_hash: HASH_B }],
            kind: "test_result",
            captured_at: "2026-01-04T00:00:00.000Z",
            result: "fail",
            summary: "Corrected.",
            producer: { type: "script", identity: "ci" },
            method: { type: "structured_command", executable: "pnpm", argv: ["pnpm", "test"] }
          }
        }),
        follow("ev-corr", 3, "evidence_voided", "ev-corr-e2", { reason: "Wrong run." }),
        follow("ev-corr", 4, "evidence_corrected", "ev-corr-e3", { replacement: { kind: "url" } })
      )
    ]
  },
  {
    name: "correction_without_replacement",
    tree: [ledger("ev-norep", recorded("ev-norep"), follow("ev-norep", 2, "evidence_corrected", "ev-norep-e1"))]
  },
  {
    name: "correction_with_falsy_replacement",
    tree: [
      ledger("ev-falsy0", recorded("ev-falsy0"), follow("ev-falsy0", 2, "evidence_corrected", "ev-falsy0-e1", { replacement: 0 })),
      ledger("ev-falsye", recorded("ev-falsye"), follow("ev-falsye", 2, "evidence_corrected", "ev-falsye-e1", { replacement: "" })),
      ledger("ev-truthy", recorded("ev-truthy"), follow("ev-truthy", 2, "evidence_corrected", "ev-truthy-e1", { replacement: "text" })),
      ledger("ev-null", recorded("ev-null"), follow("ev-null", 2, "evidence_corrected", "ev-null-e1", { replacement: null }))
    ]
  },
  {
    name: "invalidated_and_unknown_event_types",
    tree: [
      ledger("ev-inv", recorded("ev-inv"), follow("ev-inv", 2, "evidence_invalidated", "ev-inv-e1")),
      ledger("ev-unknown", recorded("ev-unknown"), follow("ev-unknown", 2, "evidence_whatever", "ev-unknown-e1"), follow("ev-unknown", 3, "evidence_voided", "ev-unknown-e1"))
    ]
  },
  {
    name: "terminal_event_stops_projection",
    tree: [
      ledger(
        "ev-stop",
        recorded("ev-stop"),
        follow("ev-stop", 2, "evidence_voided", "ev-stop-e1"),
        follow("ev-stop", 3, "evidence_corrected", "not-the-head")
      )
    ]
  },
  {
    name: "supersession_and_cycles",
    tree: [
      ledger("ev-self", recorded("ev-self"), follow("ev-self", 2, "evidence_superseded", "ev-self-e1", { replacement_evidence_id: "ev-self" })),
      ledger("ev-sup-a", recorded("ev-sup-a"), follow("ev-sup-a", 2, "evidence_superseded", "ev-sup-a-e1", { replacement_evidence_id: "ev-sup-b" })),
      ledger("ev-sup-b", recorded("ev-sup-b"), follow("ev-sup-b", 2, "evidence_superseded", "ev-sup-b-e1", { replacement_evidence_id: "ev-sup-a" })),
      ledger("ev-sup-c", recorded("ev-sup-c"), follow("ev-sup-c", 2, "evidence_superseded", "ev-sup-c-e1", { replacement_evidence_id: "ev-sup-a" })),
      ledger("ev-sup-d", recorded("ev-sup-d"), follow("ev-sup-d", 2, "evidence_superseded", "ev-sup-d-e1", { replacement_evidence_id: "ev-missing" })),
      ledger("ev-sup-e", recorded("ev-sup-e"), follow("ev-sup-e", 2, "evidence_superseded", "ev-sup-e-e1", { replacement_evidence_id: "" })),
      ledger("ev-sup-f", recorded("ev-sup-f"), follow("ev-sup-f", 2, "evidence_superseded", "ev-sup-f-e1", { replacement_evidence_id: 7 })),
      ledger("ev-sup-g", recorded("ev-sup-g"), follow("ev-sup-g", 2, "evidence_superseded", "ev-sup-g-e1"))
    ]
  },
  {
    name: "legacy_payload_shapes",
    tree: [
      ledger("ev-legacy", recorded("ev-legacy", {}, { targets: undefined, kind: undefined, captured_at: undefined, result: undefined, producer: undefined, method: undefined, use_case_ids: ["a.one", "a.two"], evidence_kind: "command_result", verdict: "fail", verifier: { type: "script" } })),
      ledger("ev-legacy2", recorded("ev-legacy2", {}, { targets: null, kind: null, result: null, producer: null, method: null, verdict: "waived", verifier: "user" })),
      ledger("ev-bare", recorded("ev-bare", { payload: {} })),
      ledger("ev-nopayload", { ...recorded("ev-nopayload"), payload: undefined, recorded_at: undefined }),
      ledger("ev-strpayload", recorded("ev-strpayload", { payload: "text" })),
      ledger("ev-arrpayload", recorded("ev-arrpayload", { payload: [1, 2] })),
      ledger("ev-primitive-targets", recorded("ev-primitive-targets", {}, { targets: [5, "x", { use_case_id: 3 }] }))
    ]
  },
  {
    name: "assurance_variants",
    tree: [
      ["url", "agent", "reported"],
      ["test_result", "script", "structured_command"],
      ["command_result", "system", "structured_command"],
      ["command_result", "user", "reported"],
      ["manual_observation", "user", "observed"],
      ["live_demo", "agent", "imported"],
      ["test_result", 5, { odd: true }]
    ].map(([kind, producer, method], index) =>
      ledger(`ev-assure-${index}`, recorded(`ev-assure-${index}`, {}, { kind, producer: { type: producer }, method: typeof method === "string" ? { type: method } : method }))
    )
  },
  {
    name: "integer_like_keys_follow_javascript_order",
    tree: [
      file(
        "evidence/by-id/ev/ev-keys.jsonl",
        `${JSON.stringify(recorded("ev-keys")).replace('"payload":{', '"payload":{"b":1,"10":2,"2":3,"-1":4,"01":5,"4294967295":6,"4294967294":7,')}\n`
      )
    ]
  },
  {
    name: "aggregates_sort_by_locale_and_state_partial",
    tree: [
      ...["ev_b", "ev-b", "ev.b", "ev0", "evB", "eva"].map((id) => ledger(id, recorded(id))),
      ledger("ev-broken", recorded("ev-broken"), follow("ev-broken", 3, "evidence_voided", "x"))
    ]
  },
  {
    name: "all_invalid_is_unusable",
    tree: [ledger("ev-only", { ...recorded("ev-only"), sequence: 2 })]
  },
  {
    name: "non_finite_number_in_duplicate_throws",
    tree: [
      file("evidence/one.jsonl", `${JSON.stringify(recorded("ev-inf")).replace('"sequence":1', '"sequence":1,"big":1e999')}\n`),
      file("evidence/two.jsonl", lines(recorded("ev-inf")))
    ]
  },
  {
    name: "non_finite_number_without_duplicate_is_kept",
    tree: [file("evidence/one.jsonl", `${JSON.stringify(recorded("ev-inf")).replace('"sequence":1', '"sequence":1,"big":1e999')}\n`)]
  },
  {
    name: "malformed_targets_string_throws",
    tree: [ledger("ev-bad-targets", recorded("ev-bad-targets", {}, { targets: "fixture.row" }))]
  },
  {
    name: "malformed_null_target_throws",
    tree: [ledger("ev-null-target", recorded("ev-null-target", {}, { targets: [null] }))]
  },
  {
    name: "malformed_use_case_ids_throws",
    tree: [ledger("ev-bad-ids", recorded("ev-bad-ids", {}, { targets: undefined, use_case_ids: "fixture.row" }))]
  },
  {
    name: "malformed_event_in_invalid_aggregate_does_not_throw",
    tree: [ledger("ev-bad-ignored", recorded("ev-bad-ignored", { sequence: 2 }, { targets: "fixture.row" }))]
  }
];

// ---------------------------------------------------------------------------
// Appending
// ---------------------------------------------------------------------------

const target = { use_case_id: "fixture.row", use_case_semantic_hash: HASH_A };

const record = (overrides = {}) => ({
  operation: "append",
  milliseconds: 1767323045678,
  random_hex: "0123456789abcdef0123",
  options: {
    idempotencyKey: "cli:fixture.row:manual_observation:pass",
    target,
    kind: "manual_observation",
    result: "pass",
    summary: "Recorded manual_observation evidence for fixture.row.",
    actorType: "agent",
    hostSurface: "codex.cli",
    ...overrides
  }
});

const voiding = (overrides = {}) => ({
  operation: "void",
  milliseconds: 1767409445000,
  random_hex: "fedcba9876543210fedc",
  options: {
    evidenceId: "019b7ca9-8f2e-7012-8345-6789abcdef01",
    expectedHeadEventId: "019b7ca9-8f2e-7012-8345-6789abcdef01",
    reason: "Recorded against the wrong row.",
    idempotencyKey: "cli:void:first",
    actorType: "agent",
    hostSurface: "codex.cli",
    ...overrides
  }
});

function runAppend(testCase) {
  const workspace = buildTree(testCase.tree);
  try {
    const context = contextFor(workspace);
    const steps = testCase.steps.map((step) => {
      clockMilliseconds = step.milliseconds;
      clockStep = step.clock_step ?? 0;
      randomHex = step.random_hex;
      let outcome;
      try {
        const call = step.operation === "append" ? appendEvidenceEvent : appendEvidenceVoidEvent;
        const result = call({ context, ...step.options });
        outcome = { result: { data: toEvidenceAppendResult(result), ledger_path: result.ledgerPath } };
      } catch (error) {
        outcome = { throws: thrown(error) };
      } finally {
        clockMilliseconds = null;
        clockStep = 0;
        randomHex = null;
      }
      return { ...step, ...outcome, lock_exists_after: existsSync(join(workspace, "evidence/.locks/append.lock")) };
    });
    restoreModes(workspace, testCase.tree);
    return tokenized({ name: testCase.name, tree: testCase.tree, steps, files_after: listTree(workspace) }, workspace);
  } finally {
    removeTree(workspace, testCase.tree);
  }
}

// The intent digest `record()`'s default options produce, taken from a real
// append so a hand-written ledger line can carry it.
function defaultIntentDigest() {
  const workspace = buildTree([]);
  try {
    clockMilliseconds = 0;
    randomHex = "00000000000000000000";
    return appendEvidenceEvent({ context: contextFor(workspace), ...record().options }).event.intent_digest;
  } finally {
    clockMilliseconds = null;
    randomHex = null;
    removeTree(workspace, []);
  }
}

const appendCases = [
  { name: "first_record_bytes", tree: [], steps: [record()] },
  {
    name: "record_every_option_shape",
    tree: [],
    steps: [
      { ...record({ idempotencyKey: "k-script", actorType: "script", kind: "command_result", result: "fail" }), milliseconds: 1 },
      { ...record({ idempotencyKey: "k-system", actorType: "system", result: "inconclusive" }), random_hex: "00000000000000000001" },
      { ...record({ idempotencyKey: "k-user", actorType: "user", result: "observed", target: { use_case_id: "fixture.row", scenario_id: "golden", use_case_semantic_hash: HASH_B } }), random_hex: "ffffffffffffffffffff" },
      {
        ...record({
          idempotencyKey: "k-method",
          actorType: "script",
          kind: "command_result",
          method: { type: "structured_command", executable: "pnpm", argv: ["pnpm", "test", "--", "é"] }
        }),
        random_hex: "a1a2a3a4a5a6a7a8a9aa"
      },
      { ...record({ idempotencyKey: "k-free", kind: "not_a_kind", result: "not_a_result", summary: "Quote \" backslash \\ newline \n tab \t control    😀" }), random_hex: "1234567890abcdef1234" }
    ]
  },
  {
    name: "clock_edges",
    tree: [],
    steps: [
      { ...record({ idempotencyKey: "k-zero" }), milliseconds: 0, random_hex: "00000000000000000002" },
      { ...record({ idempotencyKey: "k-far" }), milliseconds: 253402300799999, random_hex: "00000000000000000003" },
      { ...record({ idempotencyKey: "k-beyond" }), milliseconds: 253402300800000, random_hex: "00000000000000000004" },
      { ...record({ idempotencyKey: "k-huge" }), milliseconds: 8640000000000000, random_hex: "00000000000000000005" }
    ]
  },
  {
    name: "idempotent_replay_and_conflict",
    tree: [],
    steps: [
      record(),
      { ...record(), milliseconds: 1767323049999, random_hex: "99999999999999999999" },
      { ...record({ summary: "A different summary." }), milliseconds: 1767323050000 }
    ]
  },
  {
    name: "summary_is_redacted_before_append",
    tree: [],
    steps: [
      record({ summary: "Ran with token=abc123 and sk-abcdefghijklmnop and ghp_abcdefghijklmnopqrstuvwxyz and AKIAABCDEFGHIJKLMNOP." }),
      { ...record({ summary: "Ran with token=zzz999 and sk-abcdefghijklmnop and ghp_abcdefghijklmnopqrstuvwxyz and AKIAABCDEFGHIJKLMNOP." }), random_hex: "77777777777777777777" }
    ]
  },
  {
    name: "damaged_history_refuses_append",
    tree: [file("evidence/by-id/ev/ev-torn.jsonl", `${JSON.stringify(recorded("ev-torn"))}\n{"torn`)],
    steps: [record()]
  },
  {
    name: "append_into_existing_history",
    tree: [ledger("ev-existing", recorded("ev-existing"))],
    steps: [record({ idempotencyKey: "key-ev-existing" }), record({ idempotencyKey: "fresh" })]
  },
  {
    name: "idempotent_replay_returns_event_in_javascript_key_order",
    tree: [
      file(
        "evidence/by-id/ev/ev-keyed.jsonl",
        `${JSON.stringify({ ...recorded("ev-keyed"), idempotency_key: "keyed" }).replace('"schema_version":1', '"10":"x","schema_version":1,"2":"y"').replace('"payload":{', `"intent_digest":"${defaultIntentDigest()}","payload":{`)}\n`
      )
    ],
    steps: [record({ idempotencyKey: "keyed" })]
  },
  {
    name: "void_success_then_rejections",
    tree: [],
    steps: [
      record(),
      voiding(),
      { ...voiding({ idempotencyKey: "cli:void:again" }), random_hex: "11111111111111111111" },
      voiding({ evidenceId: "019b7ca9-8f2e-7012-8345-000000000000" })
    ]
  },
  {
    name: "void_head_mismatch",
    tree: [],
    steps: [record(), voiding({ expectedHeadEventId: "not-the-head" })]
  },
  {
    name: "void_idempotency_against_a_recorded_key",
    tree: [],
    steps: [record(), voiding({ idempotencyKey: "cli:fixture.row:manual_observation:pass" })]
  },
  {
    name: "void_idempotent_digest_matches_existing",
    tree: [ledger("ev-void-a", recorded("ev-void-a"))],
    steps: [
      record({
        idempotencyKey: "shared-void",
        target: { use_case_id: "ev-void-a", use_case_semantic_hash: ZERO_HASH },
        kind: "manual_observation",
        result: "observed",
        summary: "Recorded against the wrong row."
      }),
      voiding({ evidenceId: "ev-void-a", expectedHeadEventId: "ev-void-a-e1", idempotencyKey: "shared-void" })
    ]
  },
  {
    name: "void_into_a_ledger_outside_by_id_fails_open",
    tree: [file("evidence/legacy.jsonl", lines(recorded("zz-legacy")))],
    steps: [voiding({ evidenceId: "zz-legacy", expectedHeadEventId: "zz-legacy-e1" })]
  },
  {
    name: "void_prefix_is_two_code_units",
    tree: [ledger("évidence", recorded("évidence")), ledger("😀face", recorded("😀face"))],
    steps: [
      voiding({ evidenceId: "évidence", expectedHeadEventId: "évidence-e1" }),
      { ...voiding({ evidenceId: "😀face", expectedHeadEventId: "😀face-e1", idempotencyKey: "void-emoji" }), random_hex: "33333333333333333333" }
    ]
  },
  {
    name: "lock_timeout_when_lock_is_held",
    tree: [directory("evidence/.locks/append.lock")],
    steps: [{ ...record(), clock_step: 7000 }]
  },
  {
    name: "lock_timeout_with_a_coarse_clock",
    tree: [directory("evidence/.locks/append.lock")],
    steps: [{ ...record(), clock_step: 15000 }]
  },
  {
    name: "lock_directory_unwritable_reports_timeout",
    tree: [directory("evidence/.locks"), mode("evidence/.locks", 0o555)],
    steps: [record()]
  },
  {
    name: "evidence_root_is_a_file",
    tree: [file("evidence", "not a directory\n")],
    steps: [record()]
  }
];

// ---------------------------------------------------------------------------
// Pure functions
// ---------------------------------------------------------------------------

const assuranceInputs = [
  { kind: "url", origin: "agent", captureMethod: "reported" },
  { kind: "url", origin: "agent", captureMethod: "executed", executionMethod: "command" },
  { kind: "manual_observation", origin: "user", captureMethod: "observed" },
  { kind: "agent_observation", origin: "agent", captureMethod: "reported" },
  { kind: "command_result", origin: "script", captureMethod: "executed" },
  { kind: "test_result", origin: "script", captureMethod: "executed", exitStatus: 0, digestComputedByTool: true },
  { kind: "test_result", origin: "script", captureMethod: "executed", exitStatus: 1, digestComputedByTool: false },
  { kind: "manual_observation", origin: "system", captureMethod: "executed", executionMethod: "manual" },
  { kind: "manual_observation", origin: "system", captureMethod: "executed", executionMethod: "test" },
  { kind: "live_demo", origin: "user", captureMethod: "imported", exitStatus: -1 },
  { kind: "command_result", origin: "agent", captureMethod: "observed", executionMethod: "none" }
];

const freshnessInputs = [
  {},
  { explicitInvalidation: true },
  { explicitInvalidation: true, semanticHashMatches: false, policy: { semanticHashMismatch: "stale" } },
  { explicitInvalidation: false },
  { semanticHashMatches: false },
  { semanticHashMatches: false, policy: { semanticHashMismatch: "needs_review" } },
  { semanticHashMatches: false, policy: { semanticHashMismatch: "stale" } },
  { semanticHashMatches: true, policy: { semanticHashMismatch: "stale" } },
  { policy: { semanticHashMismatch: "stale" } }
];

function runPerformedRuns() {
  const performed = (id, overrides = {}, payload = {}) =>
    ledger(
      id,
      recorded(id, overrides, {
        kind: "command_result",
        producer: { type: "script" },
        method: { type: "structured_command", executable: "pnpm", argv: ["pnpm", "test", id] },
        ...payload
      })
    );
  const tree = [
    performed("ev-run-z", {}, { targets: [{ use_case_id: "row.z", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-a", {}, { targets: [{ use_case_id: "row.a", use_case_semantic_hash: HASH_A }, { use_case_id: "row.B", use_case_semantic_hash: HASH_A }, { use_case_id: "row.stale", use_case_semantic_hash: HASH_B }, { use_case_id: "row.unknown", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-a2", {}, { targets: [{ use_case_id: "row.a", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-fail", {}, { result: "fail", targets: [{ use_case_id: "row.fail", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-partial", {}, { verdict: "partial", targets: [{ use_case_id: "row.partial", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-verdict-pass", {}, { verdict: "pass", targets: [{ use_case_id: "row.verdict", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-reported", {}, { method: { type: "reported", argv: ["x"] }, targets: [{ use_case_id: "row.reported", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-noargv", {}, { method: { type: "structured_command" }, targets: [{ use_case_id: "row.noargv", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-emptyargv", {}, { method: { type: "structured_command", argv: [] }, targets: [{ use_case_id: "row.emptyargv", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-strargv", {}, { method: { type: "structured_command", argv: "pnpm" }, targets: [{ use_case_id: "row.strargv", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-mixedargv", {}, { method: { type: "structured_command", argv: ["pnpm", 3, null] }, targets: [{ use_case_id: "row.mixed", use_case_semantic_hash: HASH_A }] }),
    performed("ev-run-manual", {}, { kind: "manual_observation", targets: [{ use_case_id: "row.manual", use_case_semantic_hash: HASH_A }] }),
    ledger("ev-run-voided", recorded("ev-run-voided", {}, { kind: "test_result", producer: { type: "script" }, method: { type: "structured_command", argv: ["t"] }, targets: [{ use_case_id: "row.voided", use_case_semantic_hash: HASH_A }] }), follow("ev-run-voided", 2, "evidence_voided", "ev-run-voided-e1")),
    performed("ev-run-primitive", {}, { targets: [5, { use_case_id: "row.primitive", use_case_semantic_hash: HASH_A }] })
  ];
  const hashes = [
    ["row.z", HASH_A],
    ["row.a", HASH_A],
    ["row.B", HASH_A],
    ["row.stale", HASH_A],
    ["row.fail", HASH_A],
    ["row.partial", HASH_A],
    ["row.verdict", HASH_A],
    ["row.reported", HASH_A],
    ["row.noargv", HASH_A],
    ["row.emptyargv", HASH_A],
    ["row.strargv", HASH_A],
    ["row.mixed", HASH_A],
    ["row.manual", HASH_A],
    ["row.voided", HASH_A],
    ["row.primitive", HASH_A],
    ["row.a", HASH_B],
    ["row.a", HASH_A]
  ];
  const workspace = buildTree(tree);
  try {
    const snapshot = replayEvidence({ context: contextFor(workspace) });
    return { tree, hashes, runs: collectPerformedRuns(snapshot, new Map(hashes)) };
  } finally {
    removeTree(workspace, tree);
  }
}

function useCaseFile(featureId, ids) {
  return [
    "schema_version: 1",
    "feature:",
    `  id: ${featureId}`,
    "  name: Fixture feature",
    "  summary: A fixture feature.",
    "use_cases:",
    ...ids.map((id) => `  - ${JSON.stringify({ id, title: `Row ${id}`, lifecycle: "planned", value_tier: "core", journey_role: "golden", usage_frequency: "common" })}`)
  ].join("\n") + "\n";
}

function runLinks() {
  const cases = [];
  const evidence = [
    ledger("ev-link-b", recorded("ev-link-b", {}, { targets: [{ use_case_id: "link.shared", use_case_semantic_hash: HASH_A }, { use_case_id: "link.resolved", scenario_id: "golden", use_case_semantic_hash: HASH_A }] })),
    ledger("ev-link-a", recorded("ev-link-a", {}, { targets: [{ use_case_id: "link.missing", use_case_semantic_hash: HASH_A }, { use_case_id: "link.resolved", use_case_semantic_hash: "HASH" }, 5, { use_case_id: 7 }] })),
    ledger("ev-link_a", recorded("ev-link_a", {}, { targets: [{ use_case_id: "link.a", use_case_semantic_hash: HASH_A }] })),
    ledger("ev-link", recorded("ev-link", {}, { targets: [{ use_case_id: "a:b", use_case_semantic_hash: HASH_A }, { use_case_id: "a", use_case_semantic_hash: HASH_A }] }))
  ];
  const complete = [...evidence, file("use-cases/one.yml", useCaseFile("one", ["link.resolved", "link.shared"]))];
  const incomplete = [
    ...complete,
    file("use-cases/two.yml", useCaseFile("two", ["link.shared"])),
    file("use-cases/bad.yml", "schema_version: 1\nfeature: [\n")
  ];
  for (const [name, tree] of [
    ["complete_matrix", complete],
    ["incomplete_matrix", incomplete]
  ]) {
    const workspace = buildTree(tree);
    try {
      const context = contextFor(workspace);
      const snapshot = replayEvidence({ context });
      const matrix = loadUseCaseMatrix({ context });
      // Resolve the semantic hash the tree's resolved row actually carries, so
      // a "match" is exercised as well as a "mismatch".
      cases.push(tokenized({ name, tree, matrix_complete: matrix.complete, links: linkEvidenceToMatrix(snapshot, matrix) }, workspace));
    } finally {
      removeTree(workspace, tree);
    }
  }
  return cases;
}

function runLinkMatch() {
  // A second pass where the evidence carries the row's REAL semantic hash.
  const probeTree = [file("use-cases/one.yml", useCaseFile("one", ["link.resolved"]))];
  const probe = buildTree(probeTree);
  let hash;
  try {
    hash = loadUseCaseMatrix({ context: contextFor(probe) }).resolveUseCase("link.resolved").useCase.semanticHash;
  } finally {
    removeTree(probe, probeTree);
  }
  const tree = [
    ...probeTree,
    ledger("ev-match", recorded("ev-match", {}, { targets: [{ use_case_id: "link.resolved", use_case_semantic_hash: hash }] }))
  ];
  const workspace = buildTree(tree);
  try {
    const context = contextFor(workspace);
    return tokenized(
      { name: "semantic_hash_match", tree, matrix_complete: true, links: linkEvidenceToMatrix(replayEvidence({ context }), loadUseCaseMatrix({ context })) },
      workspace
    );
  } finally {
    removeTree(workspace, tree);
  }
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

function registryRecord() {
  const { UCM_ERROR_REGISTRY, UCM_ERROR_CODES, LEGACY_ENUM_CODE_MAP, LEGACY_STRING_CODE_MAP } = registryModule;
  return {
    entries: Object.entries(UCM_ERROR_REGISTRY).map(([code, item]) => ({ code, ...item })),
    codes: UCM_ERROR_CODES,
    enum_maps: Object.fromEntries(Object.entries(LEGACY_ENUM_CODE_MAP).map(([family, map]) => [family, Object.entries(map)])),
    string_map: Object.entries(LEGACY_STRING_CODE_MAP),
    markdown: renderModule.renderErrorCodesMarkdown()
  };
}

// ---------------------------------------------------------------------------
// Emit
// ---------------------------------------------------------------------------

function asciiJson(value) {
  return JSON.stringify(value).replace(
    /[-￿]/g,
    (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`
  );
}

function nameList(propertyName, names) {
  return `  static let ${propertyName}: [String] = [\n${names.map((name) => `    ${asciiJson(name)},`).join("\n")}\n  ]\n\n`;
}

const golden = {
  registry: registryRecord(),
  iso_dates: [0, 1, -1, 1767323045678, 253402300799999, 253402300800000, -62167219200000, -62167219200001, 8640000000000000, -8640000000000000].map(
    (milliseconds) => ({ milliseconds, text: new RealDate(milliseconds).toISOString() })
  ),
  assurance: assuranceInputs.map((input) => ({ input, output: deriveEvidenceAssurance(input) })),
  freshness: freshnessInputs.map((input) => ({ input, output: evaluateEvidenceFreshness(input) })),
  read: readCases.map(runRead),
  append: appendCases.map(runAppend),
  performed_runs: runPerformedRuns(),
  links: [...runLinks(), runLinkMatch()]
};

const json = asciiJson(golden);
let pounds = "#";
while (json.includes(`\\${pounds}`) || json.includes(`"""${pounds}`) || json.includes(`"${pounds}`)) {
  pounds += "#";
}
const contents = `// swiftlint:disable line_length single_line_closure_body
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript evidence ledger and error registry. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/evidence or dist/errors
// returned or wrote for the tree, clock, random bytes or options beside it.
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-evidence-corpus.mjs
enum EvidenceGoldenCorpus {
${nameList("readCaseNames", golden.read.map((item) => item.name))}${nameList("appendCaseNames", golden.append.map((item) => item.name))}${nameList("linkCaseNames", golden.links.map((item) => item.name))}  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable line_length single_line_closure_body
`;
mkdirSync(testsDirectory, { recursive: true });
const targetPath = join(testsDirectory, "EvidenceGoldenCorpus.swift");
writeFileSync(targetPath, contents);
if (!/^[\x00-\x7f]*$/.test(readFileSync(targetPath, "utf8"))) {
  throw new Error("EvidenceGoldenCorpus.swift is not ASCII");
}
console.log(
  `wrote ${targetPath}: ${golden.registry.entries.length} registry entries, ${golden.read.length} read, ` +
    `${golden.append.length} append, ${golden.links.length} link cases`
);
