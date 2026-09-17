// Regenerates `Tests/UseCasesCoreTests/Markers/Commands/ScanImpactGoldenCorpus.swift`
// by running every case below through the REAL TypeScript command cores in
// `packages/core/dist/markers/cli` and recording exactly what they return.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-scan-impact-corpus.mjs
//
// This is the oracle for scan, impact and precommit (row 3d4b). Each case has a
// SETUP the TypeScript alone runs (bind, verify, prove, hand-written evidence
// ledgers) whose resulting files become the case's `entries`; then STEPS the
// Swift test replays too (write, git, scan, impact). The clock, id factory,
// generatedAt, the signing key and the run key are fixed. The temporary root is
// recorded as `<ROOT>` everywhere, both in entries and in results.
// The script refuses to run against a `dist` older than its `src`.
//
// THIS SCRIPT WRITES MARKERS FOR A LIVING. No line of this file, and no line of
// the file it generates, may begin with a marker: marker text is built at
// runtime below, and the corpus is emitted as ONE line of escaped JSON.
import { createPrivateKey, createPublicKey } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
  chmodSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const sourceDirectory = join(repositoryRoot, "packages/core/src");
const distDirectory = join(repositoryRoot, "packages/core/dist");
const targetPath = join(
  packageRoot,
  "Tests/UseCasesCoreTests/Markers/Commands/ScanImpactGoldenCorpus.swift"
);

const PORTED = [
  "markers/cli/io",
  "markers/cli/shared",
  "markers/cli/scan",
  "markers/cli/impact",
  "markers/cli/precommit",
  "markers/cli/bind",
  "markers/cli/verify",
  "markers/cli/prove",
  "markers/scanner",
  "markers/registry",
  "markers/freshness",
  "markers/runAttestation",
  "markers/verificationContextHash",
  "markers/gitDiff",
  "markers/evidenceLedger",
  "markers/appendOnly",
  "markers/proofSignature",
  "evidence/performedRuns",
  "evidence/replayEvidence",
  "roots",
  "useCases/loadUseCaseMatrix",
  "version"
];

for (const name of PORTED) {
  const source = statSync(join(sourceDirectory, `${name}.ts`)).mtimeMs;
  const built = statSync(join(distDirectory, `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/${name}.js is older than src; rebuild packages/core first`);
  }
}

// No TypeScript call below may read the real home directory's run key: impact
// reads the default path, so the default is pointed at nothing.
process.env.UC_RUN_KEY_FILE = join(tmpdir(), "uc-scan-impact-no-run-key", "run-key");

const core = await import(join(distDirectory, "index.js"));
const {
  resolveWorkspaceContext,
  runBindCommand,
  runVerifyCommand,
  runProveCommand,
  runScanCommand,
  runImpactCommand,
  decidePrecommit,
  formatFreshnessPrSummary,
  loadMarkerRows,
  singleKeyResolver
} = core;

// A marker line, built at runtime so this file never carries one literally.
const token = (prefix) => `${prefix}: @use-` + "case:";
const startMarker = (prefix, slug) => `${token(prefix)}${slug}`;
const endMarker = (prefix, slug) => `${token(prefix)}end ${slug}`;

const plain = (value) => (value === undefined ? null : JSON.parse(JSON.stringify(value)));

// ---------------------------------------------------------------------------
// Fixed secrets.

// An ed25519 key from a fixed seed: PKCS#8 DER is a fixed prefix plus the seed.
const seed = Buffer.alloc(32, 7);
const privateKey = createPrivateKey({
  key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]),
  format: "der",
  type: "pkcs8"
});
const PUBLIC_KEY_PEM = createPublicKey(privateKey).export({ type: "spki", format: "pem" }).toString();
const KEY_ID = "ci-key-1";

const RUN_KEY = "0123456789abcdef".repeat(4);
const OTHER_RUN_KEY = "fedcba9876543210".repeat(4);
const RUN_KEY_PATH = "home/.use-cases/run-key";
const GENERATED_AT = "2026-09-17T12:00:00.000Z";

// ---------------------------------------------------------------------------
// Workspaces. Entries are relative to a temporary root; the workspace itself is
// `workspace/`, and the run key lives in `home/`.

const ROW_A = "checkout.apply_coupon";
const ROW_B = "checkout.remove_coupon";
const CHILD_ROW = "child.only_row";

const configYaml = (workspaceId, dataRoot = ".") => `schema_version: 1
workspace_id: ${workspaceId}
data_root: ${dataRoot}
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: scan-fixture
default_workflow_mode: continuous
`;

function rowYaml(rowId, title, { required = false } = {}) {
  return `  - id: ${rowId}
    title: ${title}
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: ${title}.
    preconditions:
      - A cart exists.
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: ${rowId}.web
        kind: steps
        steps:
          - The shopper submits a coupon code.
    observable_outcomes:
      - The cart total reflects the change.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        contract_check:
          kind: script
          evidence_kind: test_result
          command: [echo, contract-ok]
          inputs: []
      requirements:
        - evidence_kind: test_result
          required_verifiers: [contract_check]
          minimum_count: 1
    approval_policy:
      mode: predefined
${required ? "      required_for_release: true\n" : ""}      requirements:
        - approver_type: user
          minimum_count: 1
      statement: Final acceptance requires user-visible proof.
`;
}

function useCaseYaml(featureId, rows) {
  return `schema_version: 1
feature:
  id: ${featureId}
  name: Checkout
  summary: Shoppers can apply coupons during checkout.
metadata:
  owner: product
  lifecycle: active
use_cases:
${rows.join("")}`;
}

const rowsYaml = ({ requiredA = false, requiredB = false } = {}) =>
  useCaseYaml("checkout", [
    rowYaml(ROW_A, "Apply a valid coupon", { required: requiredA }),
    rowYaml(ROW_B, "Remove a coupon", { required: requiredB })
  ]);

const CHECKOUT_SWIFT = [
  "import Foundation",
  "",
  "struct Checkout {",
  "  func applyCoupon(_ code: String) -> Bool {",
  "    return !code.isEmpty",
  "  }",
  "",
  "  func removeCoupon() -> Bool {",
  "    return true",
  "  }",
  "}",
  ""
].join("\n");

const COUPON_PY = [
  "def apply(code):",
  "    total = 10",
  "    return total - len(code)",
  "",
  "",
  "def remove():",
  "    return 10",
  ""
].join("\n");

const file = (path, contents, mode = 0o644) => ["file", path, contents, mode];
const workspaceFile = (path, contents, mode = 0o644) => file(`workspace/${path}`, contents, mode);

const baseEntries = (options = {}) => [
  workspaceFile("use-cases.yml", configYaml("scan.fixture")),
  workspaceFile("use-cases/checkout.yml", rowsYaml(options)),
  workspaceFile("Sources/Checkout.swift", CHECKOUT_SWIFT),
  workspaceFile("tools/coupon.py", COUPON_PY)
];

const runKeyEntry = (key = RUN_KEY) => file(RUN_KEY_PATH, `${key}\n`, 0o600);

function materialize(root, entries) {
  for (const entry of entries) {
    const [kind, path] = entry;
    const full = join(root, path);
    if (kind === "directory") {
      mkdirSync(full, { recursive: true });
    } else if (kind === "file") {
      mkdirSync(dirname(full), { recursive: true });
      writeFileSync(full, entry[2]);
      chmodSync(full, entry[3]);
    } else {
      throw new Error(`unknown entry kind ${kind}`);
    }
  }
}

const jsLess = (left, right) => (left < right ? -1 : left > right ? 1 : 0);

// Every file and directory under root, skipping `.git`, sorted by path.
function snapshot(root) {
  const out = [];
  const walk = (relative) => {
    const full = relative === "" ? root : join(root, relative);
    for (const name of readdirSync(full)) {
      const childRelative = relative === "" ? name : `${relative}/${name}`;
      const childFull = join(root, childRelative);
      const status = lstatSync(childFull);
      if (status.isSymbolicLink()) {
        out.push(["symlink", childRelative, readlinkSync(childFull)]);
      } else if (status.isDirectory()) {
        if (name === ".git") {
          continue;
        }
        out.push(["directory", childRelative]);
        walk(childRelative);
      } else {
        out.push(["file", childRelative, readFileSync(childFull, "utf8"), status.mode & 0o7777]);
      }
    }
  };
  walk("");
  return out.sort((left, right) => jsLess(left[1], right[1]));
}

const gitIdentity = [
  "-c",
  "user.name=Use Cases",
  "-c",
  "user.email=use-cases@example.com",
  "-c",
  "commit.gpgsign=false"
];

// ---------------------------------------------------------------------------
// Setup actions: run by the TypeScript only; their files become the entries.

function contextFor(root, workspace = "workspace") {
  return resolveWorkspaceContext({ workspaceRoot: join(root, workspace) });
}

function ledgerPaths(context) {
  return {
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl")
  };
}

function runSetup(root, action) {
  const context = contextFor(root, action.workspace);
  const paths = ledgerPaths(context);
  let tick = 0;
  const clock = () => `2026-09-17T10:00:${String(tick++).padStart(2, "0")}.000Z`;
  const idFactory = () => `event-${String(tick++).padStart(4, "0")}`;
  if (action.kind === "bind") {
    const result = runBindCommand({
      context,
      productRoot: context.workspace_root,
      bindingsPath: paths.bindingsPath,
      clock,
      idFactory,
      version: "0.7.0",
      rowId: action.row_id,
      suffix: action.suffix,
      file: action.file,
      mode: action.mode,
      line: action.line,
      startLine: action.start_line,
      endLine: action.end_line
    });
    if (!result.ok) {
      throw new Error(`setup bind failed: ${JSON.stringify(result.errors)}`);
    }
  } else if (action.kind === "verify") {
    const result = runVerifyCommand({
      context,
      productRoot: context.workspace_root,
      ...paths,
      publicKeyResolver: () => undefined,
      trustedKeyConfigured: false,
      generatedAt: GENERATED_AT,
      all: true,
      outPath: action.out ? join(root, action.out) : join(context.data_root, ".use-cases", "verification-results.jsonl"),
      spawnRunner: () => ({ exit_code: action.exit_code ?? 0, timed_out: false, stdout: "contract-ok\n", stderr: "" }),
      repoCwd: context.workspace_root,
      runKeyPath: join(root, RUN_KEY_PATH)
    });
    if (result.exit_code > 1) {
      throw new Error(`setup verify failed: ${JSON.stringify(result)}`);
    }
  } else if (action.kind === "prove") {
    const resultsText = readFileSync(join(context.data_root, ".use-cases", "verification-results.jsonl"), "utf8");
    const verificationResults = resultsText
      .split("\n")
      .filter((line) => line.trim() !== "")
      .map((line) => JSON.parse(line));
    const result = runProveCommand({
      context,
      productRoot: context.workspace_root,
      ...paths,
      publicKeyResolver: singleKeyResolver(PUBLIC_KEY_PEM),
      all: true,
      trustedCi: true,
      append: true,
      verificationResults,
      signingKey: { privateKey, keyId: KEY_ID },
      producer: { id: "ucm-ci", version: "0.7.0", ci_run_id: "run-1", repo: "example/app", commit: "abc123" },
      generatedAt: GENERATED_AT,
      idFactory,
      repoCwd: context.workspace_root
    });
    if (result.exit_code !== 0) {
      throw new Error(`setup prove failed: ${JSON.stringify(result)}`);
    }
  } else if (action.kind === "observation") {
    // A hand-written evidence ledger naming the row's CURRENT semantic hash (or
    // a stale one), exactly as the tool's own appender lays one out.
    const loaded = loadMarkerRows(context);
    const useCase = loaded.snapshot.addressableUseCases.find((candidate) => candidate.value.id === action.row_id);
    const hash = action.stale_hash ? `sha256:${"b".repeat(64)}` : useCase.semanticHash;
    const id = action.id;
    const event = {
      schema_version: 1,
      event_type: "evidence_recorded",
      event_id: `${id}-e1`,
      aggregate_id: id,
      sequence: 1,
      recorded_at: "2026-09-01T00:00:00.000Z",
      actor_type: "agent",
      host_surface: "codex.cli",
      idempotency_key: `key-${id}`,
      payload: {
        targets: [{ use_case_id: action.row_id, use_case_semantic_hash: hash }],
        kind: "command_result",
        captured_at: "2026-09-01T00:00:00.000Z",
        result: "pass",
        summary: `Ran ${id}.`,
        producer: { type: "script" },
        method: { type: "structured_command", executable: "pnpm", argv: action.argv ?? ["pnpm", "test"] }
      }
    };
    const path = join(context.workspace_root, "evidence", "by-id", id.slice(0, 2), `${id}.jsonl`);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, `${JSON.stringify(event)}\n`);
  } else if (action.kind === "write") {
    materialize(root, [file(action.path, action.contents, action.mode ?? 0o644)]);
  } else {
    throw new Error(`unknown setup ${action.kind}`);
  }
}

// ---------------------------------------------------------------------------
// Steps: replayed by the Swift test.

const OK_LEDGER = {
  ok: true,
  exit_code: 0,
  evidence_valid: true,
  registry_valid: true,
  append_only: true,
  errors: []
};

function runScanStep(root, options) {
  const context = contextFor(root, options.workspace);
  const paths = ledgerPaths(context);
  const result = runScanCommand({
    context,
    productRoot: context.workspace_root,
    ...paths,
    evidencePath: options.evidence_path ? join(root, options.evidence_path) : paths.evidencePath,
    policyMode: options.policy_mode ?? "feature",
    publicKeyResolver: options.public_key ? singleKeyResolver(PUBLIC_KEY_PEM) : () => undefined,
    trustedKeyConfigured: options.trusted_key_configured,
    generatedAt: GENERATED_AT,
    baseRef: options.base_ref,
    repoCwd: context.workspace_root,
    resultsPath: options.results_path ? join(root, options.results_path) : undefined,
    runKeyPath: join(root, options.run_key_path ?? RUN_KEY_PATH),
    performedRuns: options.performed_runs?.map((rowId) => ({ row_id: rowId, argv: ["injected"] })),
    gate: options.gate
  });
  return {
    result: plain(result),
    precommit: plain(decidePrecommit({ validateLedger: OK_LEDGER, scan: result })),
    pr_summary: formatFreshnessPrSummary(result.status)
  };
}

function runImpactStep(root, options) {
  const context = contextFor(root, options.workspace);
  const paths = ledgerPaths(context);
  const result = runImpactCommand({
    context,
    productRoot: context.workspace_root,
    ...paths,
    publicKeyResolver: () => undefined,
    generatedAt: GENERATED_AT,
    base: options.base,
    staged: options.staged,
    repoCwd: context.workspace_root
  });
  return { result: plain(result) };
}

function runCase(testCase) {
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-scan-impact-")));
  const placeholder = (value) => JSON.parse(JSON.stringify(value).split(temporary).join("<ROOT>"));
  const restore = [];
  try {
    materialize(temporary, testCase.entries);
    for (const action of testCase.setup ?? []) {
      runSetup(temporary, action);
    }
    const entries = snapshot(temporary);
    const steps = [];
    for (const step of testCase.steps) {
      const recorded = { ...step };
      if (step.kind === "write") {
        materialize(temporary, [file(step.path, step.contents, step.mode ?? 0o644)]);
      } else if (step.kind === "remove") {
        rmSync(join(temporary, step.path), { recursive: true, force: true });
      } else if (step.kind === "chmod") {
        chmodSync(join(temporary, step.path), step.mode);
        restore.push(step.path);
      } else if (step.kind === "git") {
        execFileSync("git", step.arguments, { cwd: join(temporary, step.cwd ?? "workspace"), stdio: "pipe" });
      } else {
        const options = step.options ?? {};
        try {
          Object.assign(
            recorded,
            step.kind === "scan" ? runScanStep(temporary, options) : runImpactStep(temporary, options)
          );
        } catch (error) {
          recorded.thrown = { message: error instanceof Error ? error.message : String(error) };
        }
      }
      steps.push(recorded);
    }
    return placeholder({ name: testCase.name, entries, steps });
  } finally {
    for (const path of restore) {
      chmodSync(join(temporary, path), 0o755);
    }
    rmSync(temporary, { recursive: true, force: true });
  }
}

const scan = (options = {}) => ({ kind: "scan", options });
const impact = (options = {}) => ({ kind: "impact", options });
const write = (path, contents, mode) => ({ kind: "write", path, contents, ...(mode ? { mode } : {}) });
const git = (...args) => ({ kind: "git", arguments: args });
const gitCommit = (message) => git(...gitIdentity, "commit", "-q", "-m", message);

const bindSwift = { kind: "bind", row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 };
const bindPython = { kind: "bind", row_id: ROW_B, file: "tools/coupon.py", mode: "explicit", start_line: 6, end_line: 7 };
const verify = (extra = {}) => ({ kind: "verify", ...extra });

const results = (records) => records.map((record) => `${typeof record === "string" ? record : JSON.stringify(record)}\n`).join("");

// ---------------------------------------------------------------------------
// Scan cases.

const scanCases = [
  {
    name: "bound_and_verified_reads_verified_local",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [bindSwift, bindPython, verify()],
    steps: [scan(), scan({ gate: true }), scan({ policy_mode: "custom" })]
  },
  {
    name: "code_edit_after_verify_reads_stale_local",
    entries: [...baseEntries({ requiredA: true }), runKeyEntry()],
    setup: [bindSwift, verify()],
    steps: [
      scan(),
      { kind: "edit_inside_swift_span" },
      scan({ gate: true })
    ]
  },
  {
    name: "unbound_rows",
    entries: [...baseEntries(), runKeyEntry()],
    steps: [scan(), scan({ gate: true }), scan({ policy_mode: "release", gate: true })]
  },
  {
    name: "unbound_required_rows_block_the_gate_and_release",
    entries: [...baseEntries({ requiredA: true, requiredB: true }), runKeyEntry()],
    steps: [scan(), scan({ gate: true }), scan({ policy_mode: "release" }), scan({ policy_mode: "release", gate: true })]
  },
  {
    name: "results_ledger_absent",
    entries: [...baseEntries({ requiredA: true }), runKeyEntry()],
    setup: [bindSwift],
    steps: [scan(), scan({ gate: true })]
  },
  {
    name: "results_ledger_at_an_overridden_path",
    entries: [...baseEntries({ requiredA: true }), runKeyEntry()],
    setup: [bindSwift, verify({ out: "elsewhere/results.jsonl" })],
    steps: [scan(), scan({ results_path: "elsewhere/results.jsonl", gate: true }), scan({ results_path: "missing/results.jsonl" })]
  },
  {
    name: "run_key_absent_mismatched_or_malformed",
    entries: [...baseEntries({ requiredA: true }), runKeyEntry()],
    setup: [
      bindSwift,
      verify(),
      { kind: "write", path: "home/other-key", contents: `${OTHER_RUN_KEY}\n` },
      { kind: "write", path: "home/malformed-key", contents: "not-a-key\n" },
      { kind: "write", path: "home/padded-key", contents: `  \n${RUN_KEY}\t\n` }
    ],
    steps: [
      scan({ run_key_path: "home/absent-key", gate: true }),
      scan({ run_key_path: "home/other-key" }),
      scan({ run_key_path: "home/malformed-key" }),
      scan({ run_key_path: "home/padded-key", gate: true })
    ]
  },
  {
    name: "results_ledger_with_odd_lines",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [
      bindSwift,
      bindPython,
      verify(),
      {
        kind: "write",
        path: "workspace/.use-cases/extra.jsonl",
        contents: results([
          "",
          "   ",
          "not json",
          "[1,2]",
          "null",
          "42",
          { row_id: ROW_B, verification_context_hash: 1, binding_set_hash: "x", status: "pass" },
          { row_id: ROW_B, verification_context_hash: "x", binding_set_hash: "x", status: "fail" }
        ])
      }
    ],
    steps: [scan(), scan({ results_path: "workspace/.use-cases/extra.jsonl" })]
  },
  {
    name: "non_finite_number_in_the_results_ledger",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [
      bindSwift,
      {
        kind: "write",
        path: "workspace/.use-cases/verification-results.jsonl",
        contents: `{"row_id":"${ROW_A}","verification_context_hash":"x","binding_set_hash":"x","status":"pass","n":1e999,"run_attestation":"hmac-sha256:00"}\n`
      }
    ],
    steps: [scan(), scan({ run_key_path: "home/absent-key" })]
  },
  {
    name: "failed_verification_is_not_green",
    entries: [...baseEntries({ requiredA: true }), runKeyEntry()],
    setup: [bindSwift, verify({ exit_code: 1 })],
    steps: [scan({ gate: true })]
  },
  {
    name: "invalid_marker_exits_three",
    entries: [...baseEntries({ requiredA: true }), runKeyEntry()],
    setup: [
      bindSwift,
      {
        kind: "write",
        path: "workspace/tools/broken.py",
        contents: `${startMarker("#", "Not A Slug!")}\nprint(1)\n`
      }
    ],
    steps: [scan(), scan({ gate: true }), scan({ policy_mode: "release", gate: true })]
  },
  {
    name: "unregistered_marker_exits_three",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [
      {
        kind: "write",
        path: "workspace/tools/stray.py",
        contents: `${startMarker("#", ROW_B)}\nprint(1)\n${endMarker("#", ROW_B)}\n`
      }
    ],
    steps: [scan()]
  },
  {
    name: "damaged_registry_exits_four",
    entries: [...baseEntries({ requiredA: true }), runKeyEntry()],
    setup: [
      bindSwift,
      { kind: "write", path: "workspace/.use-cases/bindings.jsonl", contents: "{not json\n" },
      {
        kind: "write",
        path: "workspace/tools/broken.py",
        contents: `${startMarker("#", "Not A Slug!")}\nprint(1)\n`
      }
    ],
    steps: [scan(), scan({ policy_mode: "release", gate: true })]
  },
  {
    name: "damaged_evidence_exits_four",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [bindSwift, { kind: "write", path: "workspace/.use-cases/proofs.jsonl", contents: '{"schema":"ucase-proof-event-v1"}\nnot json\n' }],
    steps: [scan(), scan({ trusted_key_configured: false }), scan({ gate: true })]
  },
  {
    name: "signed_proof_fresh_with_key_and_keyless_without",
    entries: [...baseEntries({ requiredA: true }), runKeyEntry()],
    setup: [bindSwift, verify(), { kind: "prove" }],
    steps: [
      scan({ public_key: true, policy_mode: "release", gate: true }),
      scan({ trusted_key_configured: false, policy_mode: "release", gate: true }),
      scan({ policy_mode: "release" }),
      scan({ trusted_key_configured: true }),
      { kind: "edit_inside_swift_span" },
      scan({ public_key: true, policy_mode: "release", gate: true })
    ]
  },
  {
    name: "rewritten_evidence_ledger_passes_the_base_ref_check",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [bindSwift, verify(), { kind: "prove" }],
    steps: [
      git("init", "-q", "-b", "main"),
      git("add", "-A"),
      gitCommit("base"),
      scan({ public_key: true, base_ref: "HEAD" }),
      { kind: "rewrite_first_proof" },
      scan({ public_key: true, base_ref: "HEAD" }),
      scan({ public_key: true, base_ref: "no-such-ref" })
    ]
  },
  {
    name: "base_ref_outside_a_repository_throws",
    entries: [...baseEntries(), runKeyEntry()],
    steps: [scan({ base_ref: "HEAD" })]
  },
  {
    name: "performed_runs_from_the_observation_ledger",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [
      bindSwift,
      bindPython,
      { kind: "observation", id: "ev-run-a", row_id: ROW_A, argv: ["pnpm", 3, null] },
      { kind: "observation", id: "ev-run-b", row_id: ROW_B, stale_hash: true }
    ],
    steps: [scan(), scan({ performed_runs: [ROW_B] }), scan({ performed_runs: [] })]
  },
  {
    name: "damaged_observation_ledger_yields_no_performed_runs",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [
      bindSwift,
      { kind: "observation", id: "ev-run-a", row_id: ROW_A },
      { kind: "write", path: "workspace/evidence/by-id/zz/zz-broken.jsonl", contents: "{broken\n" }
    ],
    steps: [scan()]
  },
  {
    name: "unlistable_observation_ledger_yields_no_performed_runs",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [bindSwift, { kind: "observation", id: "ev-run-a", row_id: ROW_A }],
    steps: [scan(), { kind: "chmod", path: "workspace/evidence/by-id/ev", mode: 0o300 }, scan()]
  },
  {
    name: "nested_workspace_and_its_own_scan",
    entries: [
      ...baseEntries(),
      runKeyEntry(),
      workspaceFile("child/use-cases.yml", configYaml("child.fixture")),
      workspaceFile("child/use-cases/child.yml", useCaseYaml("child", [rowYaml(CHILD_ROW, "Child row")])),
      workspaceFile("child/lib/child.py", "def child():\n    return 1\n")
    ],
    setup: [
      bindSwift,
      { kind: "bind", workspace: "workspace/child", row_id: CHILD_ROW, file: "lib/child.py", mode: "explicit", start_line: 1, end_line: 2 }
    ],
    steps: [scan(), scan({ workspace: "workspace/child" })]
  },
  {
    name: "data_root_is_not_walked",
    entries: [
      file("workspace/use-cases.yml", configYaml("scan.fixture", "data")),
      file("workspace/data/use-cases/checkout.yml", rowsYaml()),
      workspaceFile("Sources/Checkout.swift", CHECKOUT_SWIFT),
      workspaceFile("data/notes.py", `${startMarker("#", "Not A Slug!")}\nprint(1)\n`),
      runKeyEntry()
    ],
    setup: [bindSwift, verify()],
    steps: [scan()]
  }
];

// ---------------------------------------------------------------------------
// Impact cases: every one runs against a real git repository.

const committedBoundRepository = (extra = []) => ({
  entries: [...baseEntries(), runKeyEntry(), ...extra],
  setup: [bindSwift, bindPython],
  base: [git("init", "-q", "-b", "main"), git("add", "-A"), gitCommit("base")]
});

function impactCase(name, prepared, steps) {
  return { name, entries: prepared.entries, setup: prepared.setup, steps: [...prepared.base, ...steps] };
}

const impactCases = [
  impactCase("no_changes", committedBoundRepository(), [impact(), impact({ staged: true }), impact({ base: "HEAD" })]),
  impactCase("modified_inside_and_outside_bound_spans", committedBoundRepository(), [
    { kind: "edit_inside_swift_span" },
    { kind: "edit", path: "workspace/tools/coupon.py", find: "    total = 10", replace: "    total = 11" },
    write("workspace/README.md", "# new\n"),
    impact(),
    impact({ staged: true }),
    git("add", "-A"),
    impact({ staged: true }),
    impact({ base: "HEAD" }),
    gitCommit("edit"),
    impact(),
    impact({ base: "HEAD~1" })
  ]),
  impactCase("deleted_bound_file", committedBoundRepository(), [
    { kind: "remove", path: "workspace/tools/coupon.py" },
    impact(),
    git("add", "-A"),
    impact({ staged: true })
  ]),
  impactCase("deleted_bound_file_against_an_older_base", committedBoundRepository(), [
    { kind: "remove", path: "workspace/tools/coupon.py" },
    git("add", "-A"),
    gitCommit("delete"),
    impact({ base: "HEAD~1" }),
    impact()
  ]),
  impactCase("renamed_bound_file_keeps_its_marker", committedBoundRepository(), [
    git("mv", "tools/coupon.py", "tools/coupons.py"),
    impact(),
    impact({ staged: true })
  ]),
  impactCase("renamed_bound_file_losing_its_marker", committedBoundRepository(), [
    git("mv", "Sources/Checkout.swift", "Sources/Basket.swift"),
    write("workspace/Sources/Basket.swift", CHECKOUT_SWIFT),
    git("add", "-A"),
    impact({ staged: true }),
    impact()
  ]),
  impactCase("marker_removed_from_a_modified_file", committedBoundRepository(), [
    write("workspace/tools/coupon.py", COUPON_PY),
    impact(),
    { kind: "edit", path: "workspace/Sources/Checkout.swift", find: "struct Checkout {", replace: "struct Checkout {\n  // added above the marker" },
    impact()
  ]),
  impactCase("missing_base_ref", committedBoundRepository(), [impact({ base: "no-such-ref" })]),
  {
    name: "not_a_git_repository",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [bindSwift],
    steps: [impact(), impact({ staged: true }), impact({ base: "main" })]
  },
  {
    name: "repository_without_commits",
    entries: [...baseEntries(), runKeyEntry()],
    setup: [bindSwift],
    steps: [git("init", "-q", "-b", "main"), impact()]
  },
  {
    name: "nested_workspace_inside_a_repository",
    entries: [
      file("repo/README.md", "# repo\n"),
      ...baseEntries().map(([kind, path, contents, mode]) => [kind, path.replace(/^workspace\//, "workspace/app/"), contents, mode]),
      runKeyEntry()
    ],
    setup: [{ ...bindSwift, workspace: "workspace/app" }],
    steps: [
      git("init", "-q", "-b", "main"),
      git("add", "-A"),
      gitCommit("base"),
      { kind: "edit_inside_swift_span", path: "workspace/app/Sources/Checkout.swift" },
      impact({ workspace: "workspace/app" })
    ]
  }
];

// ---------------------------------------------------------------------------
// Run everything, resolving the content-dependent steps inside the run.

function runCaseWithDynamicSteps(testCase) {
  // The dynamic steps depend on bytes the setup produced, so a dry run records
  // those bytes first and the real run replays them as writes.
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-scan-impact-probe-")));
  try {
    materialize(temporary, testCase.entries);
    for (const action of testCase.setup ?? []) {
      runSetup(temporary, action);
    }
    const steps = testCase.steps.map((step) => {
      if (step.kind === "edit_inside_swift_span") {
        const path = step.path ?? "workspace/Sources/Checkout.swift";
        const text = readFileSync(join(temporary, path), "utf8");
        return write(path, text.replace("return !code.isEmpty", "return code.count > 1"));
      }
      if (step.kind === "edit") {
        const text = readFileSync(join(temporary, step.path), "utf8");
        if (!text.includes(step.find)) {
          throw new Error(`edit target missing in ${step.path}`);
        }
        return write(step.path, text.replace(step.find, step.replace));
      }
      if (step.kind === "rewrite_first_proof") {
        const path = "workspace/.use-cases/proofs.jsonl";
        const text = readFileSync(join(temporary, path), "utf8");
        if (!text.startsWith("{")) {
          throw new Error("no proof to rewrite");
        }
        // Same JSON, different bytes: one space after the opening brace.
        return write(path, `{ ${text.slice(1)}`);
      }
      return step;
    });
    return runCase({ ...testCase, steps });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

const scanResults = scanCases.map(runCaseWithDynamicSteps);
const impactResults = impactCases.map(runCaseWithDynamicSteps);

// ---------------------------------------------------------------------------
// Precommit: the pure decision over hand-varied inputs. Each input starts from a
// real scan result above and changes only what a combination needs.

const scanStep = (caseName, index) => {
  const found = scanResults.find((entry) => entry.name === caseName);
  const steps = found.steps.filter((step) => step.kind === "scan");
  return JSON.parse(JSON.stringify(steps[index].result));
};

const sliceScan = (result) => ({
  exit_code: result.exit_code,
  registry_valid: result.registry_valid,
  evidence_valid: result.evidence_valid,
  status: result.status
});

function withRow(status, rowIndex, changes) {
  const rows = status.rows.map((row, index) => {
    if (index !== rowIndex) {
      return row;
    }
    const next = { ...row };
    for (const [key, value] of Object.entries(changes)) {
      if (value === undefined) {
        delete next[key];
      } else {
        next[key] = value;
      }
    }
    return next;
  });
  return { ...status, rows };
}

const unbound = sliceScan(scanStep("unbound_rows", 0));
const verified = sliceScan(scanStep("bound_and_verified_reads_verified_local", 0));
const invalid = sliceScan(scanStep("invalid_marker_exits_three", 0));
const damagedRegistry = sliceScan(scanStep("damaged_registry_exits_four", 0));
const releaseBlocked = sliceScan(scanStep("unbound_required_rows_block_the_gate_and_release", 2));
const fresh = sliceScan(scanStep("signed_proof_fresh_with_key_and_keyless_without", 0));
const suspect = sliceScan(scanStep("signed_proof_fresh_with_key_and_keyless_without", 4));
const damagedEvidence = sliceScan(scanStep("damaged_evidence_exits_four", 0));

const ledgerError = (scope, code, message) => ({ scope, code, line: 3, message });

const precommitInputs = [
  { name: "all_unbound_warns", validateLedger: OK_LEDGER, scan: unbound },
  { name: "verified_local_still_warns_as_unproven", validateLedger: OK_LEDGER, scan: verified },
  { name: "fresh_row_beside_an_unbound_row_warns", validateLedger: OK_LEDGER, scan: fresh },
  { name: "suspect_in_release_mode_blocks", validateLedger: OK_LEDGER, scan: suspect },
  { name: "invalid_row_blocks", validateLedger: OK_LEDGER, scan: invalid },
  { name: "release_policy_block_blocks", validateLedger: OK_LEDGER, scan: releaseBlocked },
  { name: "scan_registry_invalid_with_ledger_errors", validateLedger: OK_LEDGER, scan: damagedRegistry },
  { name: "scan_evidence_invalid_with_ledger_errors", validateLedger: OK_LEDGER, scan: damagedEvidence },
  {
    name: "scan_ledger_invalid_without_ledger_level_errors",
    validateLedger: OK_LEDGER,
    scan: { ...fresh, evidence_valid: false }
  },
  {
    name: "scan_ledger_invalid_integrity_error_shapes",
    validateLedger: OK_LEDGER,
    scan: {
      ...fresh,
      registry_valid: false,
      status: {
        ...fresh.status,
        integrity_errors: [
          { code: "NO_MESSAGE" },
          { code: "NULL_MESSAGE", message: null },
          { code: "EMPTY_MESSAGE", message: "" },
          { code: "NULL_ROW", message: "kept", row_id: null },
          { code: "ROW_BOUND", message: "dropped", row_id: ROW_A }
        ]
      }
    }
  },
  { name: "scan_usage_error_blocks", validateLedger: OK_LEDGER, scan: { ...fresh, exit_code: 2 } },
  { name: "scan_exit_three_alone_does_not_block", validateLedger: OK_LEDGER, scan: { ...fresh, exit_code: 3 } },
  {
    name: "ledger_not_ok_without_errors",
    validateLedger: { ...OK_LEDGER, ok: false, exit_code: 4 },
    scan: fresh
  },
  {
    name: "ledger_not_ok_with_errors",
    validateLedger: {
      ...OK_LEDGER,
      ok: false,
      exit_code: 4,
      errors: [ledgerError("evidence", "BAD_SIGNATURE", "bad"), ledgerError("registry", "APPEND_ONLY_VIOLATION", "edited")]
    },
    scan: unbound
  },
  {
    name: "ledger_ok_with_errors_ignores_them",
    validateLedger: { ...OK_LEDGER, errors: [ledgerError("evidence", "BAD_SIGNATURE", "bad")] },
    scan: fresh
  },
  {
    name: "row_shapes",
    validateLedger: OK_LEDGER,
    scan: {
      ...unbound,
      status: withRow(
        withRow(unbound.status, 0, { required_action: "", reasons: [] }),
        1,
        { status: "SUSPECT", required_action: null, reasons: [{ detail: "no code" }] }
      )
    }
  },
  {
    name: "policy_block_on_every_status",
    validateLedger: OK_LEDGER,
    scan: {
      ...unbound,
      status: withRow(
        withRow(unbound.status, 0, { status: "FRESH", policy_block: true, required_action: "" }),
        1,
        { status: "INVALID", policy_block: true }
      )
    }
  },
  {
    name: "unproven_with_custom_required_action",
    validateLedger: OK_LEDGER,
    scan: {
      ...unbound,
      status: withRow(unbound.status, 0, { status: "UNPROVEN", required_action: "run the thing" })
    }
  },
  {
    name: "no_rows_is_ok",
    validateLedger: OK_LEDGER,
    scan: { ...unbound, status: { ...unbound.status, rows: [] } }
  },
  {
    name: "everything_at_once",
    validateLedger: { ...OK_LEDGER, ok: false, exit_code: 4 },
    scan: { ...damagedRegistry, exit_code: 2, status: withRow(damagedRegistry.status, 1, { status: "SUSPECT" }) }
  }
];

const precommitCases = precommitInputs.map((input) => ({
  name: input.name,
  validate_ledger: input.validateLedger,
  scan: input.scan,
  output: plain(decidePrecommit({ validateLedger: input.validateLedger, scan: input.scan })),
  pr_summary: formatFreshnessPrSummary(input.scan.status)
}));

// ---------------------------------------------------------------------------
// Emit.

const corpus = {
  public_key_pem: PUBLIC_KEY_PEM,
  run_key_path: RUN_KEY_PATH,
  generated_at: GENERATED_AT,
  validate_ledger_ok: OK_LEDGER,
  scan_cases: scanResults,
  impact_cases: impactResults,
  precommit_cases: precommitCases
};

// Every non-ASCII code unit (including each half of a surrogate pair) becomes
// a \uXXXX escape, so the emitted Swift file is pure ASCII and ONE line.
const asciiJson = JSON.stringify(corpus).replace(
  /[-￿]/g,
  (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`
);

let pounds = "#";
while (asciiJson.includes(`\\${pounds}`) || asciiJson.includes(`"""${pounds}`)) {
  pounds += "#";
}

const names = (cases) => cases.map((entry) => `    ${JSON.stringify(entry.name)},`).join("\n");
const nameList = (label, cases) => `  static let ${label}: [String] = [\n${names(cases)}\n  ]\n`;

const swift = `// swiftlint:disable single_line_closure_body line_length
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript scan, impact and precommit cores. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/markers/cli returned for the
// input beside it. The temporary root is spelled <ROOT>.
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-scan-impact-corpus.mjs
enum ScanImpactGoldenCorpus {
${nameList("scanCaseNames", scanResults)}
${nameList("impactCaseNames", impactResults)}
${nameList("precommitCaseNames", precommitCases)}
  /// The corpus itself: one JSON object, ASCII only, on one line.
  static let json = ${pounds}"""
  ${asciiJson}
  """${pounds}
}

// swiftlint:enable single_line_closure_body line_length
`;

mkdirSync(dirname(targetPath), { recursive: true });
writeFileSync(targetPath, swift);
const written = readFileSync(targetPath, "utf8");
if (!/^[\x00-\x7f]*$/.test(written)) {
  throw new Error("corpus file is not ASCII");
}
if (/^[ \t]*(\/\/|#): @use-case:/m.test(written)) {
  throw new Error("corpus file carries a marker line");
}
console.log(
  `wrote ${targetPath}: ${scanResults.length} scan, ${impactResults.length} impact, ` +
    `${precommitCases.length} precommit cases`
);
