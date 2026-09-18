// Regenerates `Tests/UseCasesCoreTests/Markers/MarkersFreshnessGoldenCorpus.swift`
// by running every case below through the REAL TypeScript marker code in
// `packages/core/dist/markers` and recording exactly what it returns.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-markers-freshness-corpus.mjs
//
// This is the oracle for the verifier presets, the verifier resolver, the
// verification context hash and the freshness state machine (row 3d3). The
// freshness object IS the `use-cases scan` contract (ADR 0007 decision 8), so each case
// records the whole object as the bytes `JSON.stringify` wrote: key order,
// absent members and `null` members are all part of what the Swift port is held
// to. The script refuses to run against a `dist` older than its `src`.
//
// A custom policy predicate is a function and cannot travel as data, so each
// case NAMES one from `CUSTOM_POLICIES` below; the Swift side keeps the same
// named set.
//
// Run with NODE_V8_COVERAGE=<dir> to collect the block coverage the corpus
// reaches in freshness.js (see `report-freshness-coverage.mjs`).
import { readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const sourceDirectory = join(repositoryRoot, "packages/core/src/markers");
const distDirectory = join(repositoryRoot, "packages/core/dist/markers");
const targetPath = join(
  packageRoot,
  "Tests/UseCasesCoreTests/Markers/MarkersFreshnessGoldenCorpus.swift"
);

const PORTED = [
  "verifierPresets",
  "verifierResolver",
  "verificationContextHash",
  "freshness",
  "canonicalJson",
  "rowHash",
  "policyHash",
  "bindingSetHash",
  "reconcile",
  "markerLine",
  "scanner"
];

for (const name of PORTED) {
  const source = statSync(join(sourceDirectory, `${name}.ts`)).mtimeMs;
  const built = statSync(join(distDirectory, `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/markers/${name}.js is older than src; rebuild packages/core first`);
  }
}

const markers = await import(join(distDirectory, "index.js"));
const {
  VERIFIER_PRESET_IDS,
  isTestSuitePreset,
  isVerifierPresetId,
  expandPreset,
  resolveRowVerifiers,
  computeVerificationContextHash,
  computeRowVerificationContextHash,
  VERIFICATION_CONTEXT_HASH_ID,
  DEFAULT_CONVENTION_VERIFIER_ID,
  deriveFreshness,
  computeRowHash,
  computeVerificationPolicyHash,
  computeApprovalPolicyHash,
  computeBindingSetHash,
  scanFiles
} = markers;

// A marker line, built at runtime so this file never carries one literally.
const markerToken = (prefix) => `${prefix}: @use-` + "case:";
const lines = (...parts) => parts.join("\n");
const explicitBlock = (slug, body = "x = 1") =>
  lines(`${markerToken("#")}${slug}`, body, `${markerToken("#")}end ${slug}`);

const hash = (digit) => `sha256:${digit.repeat(64)}`;

// ---------------------------------------------------------------------------
// verifier presets
// ---------------------------------------------------------------------------

const presetInputs = [
  ...VERIFIER_PRESET_IDS.map((id) => ({ name: `preset_${id}`, preset: id, slug: "checkout.apply_coupon" })),
  { name: "unknown_preset", preset: "ruby.rspec", slug: "a.b" },
  { name: "preset_id_case_differs", preset: "JS.vitest", slug: "a.b" },
  { name: "empty_preset_id", preset: "", slug: "a.b" },
  { name: "variant_substituted_after_slug", preset: "js.vitest", slug: "fam{variant}", variant: "dark" },
  { name: "variant_without_token", preset: "python.pytest", slug: "a.b", variant: "x" },
  { name: "slug_token_repeated_in_slug", preset: "make.target", slug: "{slug}{slug}" },
  { name: "non_ascii_slug", preset: "js.vitest", slug: "caf\u00e9.\ud83d\ude00" },
  { name: "empty_slug", preset: "python.pytest", slug: "" },
  { name: "variant_is_empty_string", preset: "js.vitest", slug: "x{variant}y", variant: "" }
];

const presetCases = presetInputs.map((entry) => ({
  ...entry,
  is_preset_id: isVerifierPresetId(entry.preset),
  expansion: expandPreset(entry.preset, entry.slug, entry.variant)
}));

const testSuitePresetCases = [
  ...VERIFIER_PRESET_IDS,
  "ruby.rspec",
  "",
  "JS.vitest"
].map((preset) => ({ preset, is_test_suite: isTestSuitePreset(preset) }));
testSuitePresetCases.push({ preset: null, is_test_suite: isTestSuitePreset(undefined) });

// ---------------------------------------------------------------------------
// verifier resolver
// ---------------------------------------------------------------------------

const requirements = (...ids) => ({
  mode: "requirements",
  requirements: [{ evidence_kind: "test_result", required_verifiers: ids, minimum_count: 1 }]
});

const script = (overrides = {}) => ({
  kind: "script",
  evidence_kind: "test_result",
  command: ["swift", "test", "--filter", "{slug}"],
  inputs: ["Tests/{slug}.swift"],
  ...overrides
});

// `workspace` is the resolver's input shape exactly: the normalized
// `{ default?, verifiers }` a resolved workspace context carries.
const resolverInputs = {
  policy_not_an_object: { policy: "requirements", slug: "a.b" },
  policy_null: { policy: null, slug: "a.b" },
  policy_absent: { slug: "a.b" },
  policy_is_an_array: { policy: [requirements("unit")], slug: "a.b" },
  mode_not_requirements: { policy: { ...requirements("unit"), mode: "any" }, slug: "a.b" },
  requirements_not_an_array: { policy: { mode: "requirements", requirements: {} }, slug: "a.b" },
  requirement_not_an_object: {
    policy: { mode: "requirements", requirements: [null, "unit", { required_verifiers: ["unit"] }] },
    slug: "a.b",
    workspace: { verifiers: { unit: script() } }
  },
  required_verifiers_not_an_array: {
    policy: { mode: "requirements", requirements: [{ required_verifiers: "unit" }] },
    slug: "a.b"
  },
  non_string_ids_skipped_duplicates_collapsed: {
    policy: {
      mode: "requirements",
      requirements: [
        { required_verifiers: ["unit", 7, null, "unit"] },
        { required_verifiers: ["ui", "unit"] }
      ]
    },
    slug: "a.b",
    workspace: { verifiers: { unit: script(), ui: script({ command: ["ui"] }) } }
  },
  row_script_with_slug_everywhere: {
    policy: { ...requirements("unit"), verifiers: { unit: script({ timeout_seconds: 90 }) } },
    slug: "checkout.apply_coupon"
  },
  row_script_loose_members: {
    policy: {
      ...requirements("unit"),
      verifiers: {
        unit: { command: ["a", 1, "{slug}", null], inputs: "not-an-array", evidence_kind: 5, timeout_seconds: "90" }
      }
    },
    slug: "a.b"
  },
  row_script_without_command_or_inputs: {
    policy: { ...requirements("unit"), verifiers: { unit: {} } },
    slug: "a.b"
  },
  row_script_fractional_timeout: {
    policy: { ...requirements("unit"), verifiers: { unit: script({ timeout_seconds: 2.5 }) } },
    slug: "a.b"
  },
  row_script_variant_tokens: {
    policy: {
      ...requirements("unit"),
      verifiers: { unit: script({ command: ["run", "{slug}::{variant}"], inputs: ["t/{variant}/{slug}"] }) }
    },
    slug: "fam",
    variant: "dark"
  },
  row_script_variant_token_without_variant: {
    policy: {
      ...requirements("unit"),
      verifiers: { unit: script({ command: ["run", "{slug}::{variant}"] }) }
    },
    slug: "fam"
  },
  row_preset: {
    policy: { ...requirements("unit"), verifiers: { unit: { preset: "js.vitest" } } },
    slug: "checkout.apply_coupon"
  },
  row_preset_with_overrides: {
    policy: {
      ...requirements("unit"),
      verifiers: {
        unit: {
          preset: "python.pytest",
          evidence_kind: "live_demo",
          timeout_seconds: 30,
          inputs: ["x/{slug}", 3, "y/{variant}"],
          command: ["ignored"]
        }
      }
    },
    slug: "a.b",
    variant: "v1"
  },
  row_preset_empty_inputs_override: {
    policy: { ...requirements("unit"), verifiers: { unit: { preset: "js.vitest", inputs: [] } } },
    slug: "a.b"
  },
  row_preset_unknown: {
    policy: { ...requirements("unit"), verifiers: { unit: { preset: "ruby.rspec" } } },
    slug: "a.b"
  },
  row_preset_not_a_string_is_a_script: {
    policy: { ...requirements("unit"), verifiers: { unit: { preset: 7, command: ["x"] } } },
    slug: "a.b"
  },
  row_verifier_not_a_record_falls_to_workspace: {
    policy: { ...requirements("unit"), verifiers: { unit: "js.vitest" } },
    slug: "a.b",
    workspace: { verifiers: { unit: script({ command: ["from-workspace"] }) } }
  },
  row_verifiers_not_a_record: {
    policy: { ...requirements("unit"), verifiers: ["unit"] },
    slug: "a.b",
    workspace: { verifiers: { unit: script() } }
  },
  row_wins_over_workspace: {
    policy: { ...requirements("unit"), verifiers: { unit: script({ command: ["row"] }) } },
    slug: "a.b",
    workspace: { verifiers: { unit: script({ command: ["workspace"] }) } }
  },
  workspace_config_preset: {
    policy: requirements("unit"),
    slug: "a.b",
    workspace: { verifiers: { unit: { preset: "go.test", evidence_kind: "build" } } }
  },
  acceptance_uses_workspace_default: {
    policy: requirements(DEFAULT_CONVENTION_VERIFIER_ID),
    slug: "a.b",
    workspace: { default: "vitest", verifiers: { vitest: { preset: "js.vitest" } } }
  },
  acceptance_default_names_nothing: {
    policy: requirements(DEFAULT_CONVENTION_VERIFIER_ID),
    slug: "a.b",
    workspace: { default: "missing", verifiers: {} }
  },
  acceptance_default_names_a_non_record: {
    policy: requirements(DEFAULT_CONVENTION_VERIFIER_ID),
    slug: "a.b",
    workspace: { default: "vitest", verifiers: { vitest: "js.vitest" } }
  },
  acceptance_declared_directly_beats_default: {
    policy: requirements(DEFAULT_CONVENTION_VERIFIER_ID),
    slug: "a.b",
    workspace: {
      default: "vitest",
      verifiers: { vitest: { preset: "js.vitest" }, acceptance: script({ command: ["direct"] }) }
    }
  },
  acceptance_without_default_is_blocked: {
    policy: requirements(DEFAULT_CONVENTION_VERIFIER_ID),
    slug: "a.b",
    workspace: { verifiers: { vitest: { preset: "js.vitest" } } }
  },
  default_only_applies_to_acceptance: {
    policy: requirements("unit"),
    slug: "a.b",
    workspace: { default: "vitest", verifiers: { vitest: { preset: "js.vitest" } } }
  },
  default_to_unknown_preset_is_blocked_by_preset: {
    policy: requirements(DEFAULT_CONVENTION_VERIFIER_ID),
    slug: "a.b",
    workspace: { default: "bad", verifiers: { bad: { preset: "nope" } } }
  },
  unresolvable_is_blocked: { policy: requirements("unit"), slug: "a.b" },
  no_workspace_at_all: { policy: requirements("unit"), slug: "a.b", workspace: null },
  sorted_by_code_unit: {
    policy: {
      mode: "requirements",
      requirements: [{ required_verifiers: ["b", "B", "a_b", "a-b", "\u00e9", "e\u0301", "\uffff", "\ud83d\ude00", "a"] }]
    },
    slug: "a.b",
    workspace: { verifiers: { a: script(), "\u00e9": script({ command: ["precomposed"] }) } }
  },
  equivalent_row_verifier_ids_stay_distinct: {
    policy: {
      mode: "requirements",
      requirements: [{ required_verifiers: ["e\u0301", "\u00e9"] }],
      verifiers: { "\u00e9": script({ command: ["precomposed"] }), "e\u0301": script({ command: ["decomposed"] }) }
    },
    slug: "a.b"
  }
};

const resolverCases = Object.entries(resolverInputs).map(([name, entry]) => {
  const row = { slug: entry.slug, verification_policy: entry.policy };
  if (entry.variant !== undefined) {
    row.variant = entry.variant;
  }
  const workspace = entry.workspace === null ? undefined : entry.workspace ?? {};
  return {
    name,
    slug: entry.slug,
    variant: entry.variant ?? null,
    has_policy: Object.hasOwn(entry, "policy"),
    policy: entry.policy ?? null,
    workspace: entry.workspace ?? null,
    resolved: resolveRowVerifiers(row, workspace)
  };
});

// ---------------------------------------------------------------------------
// verification context hash
// ---------------------------------------------------------------------------

// A fake read-only filesystem: an exact-path map, recording every path read.
function fakeFs(files) {
  const reads = [];
  return {
    reads,
    readText(path) {
      reads.push(path);
      return Object.hasOwn(files, path) ? files[path] : null;
    }
  };
}

const contextInputs = {
  lockfile_present: {
    policy: requirements("unit"),
    workspace: { verifiers: { unit: script({ inputs: [] }) } },
    files: { "/repo/pnpm-lock.yaml": "lockfileVersion: '9.0'\n" }
  },
  lockfile_absent: {
    policy: requirements("unit"),
    workspace: { verifiers: { unit: script({ inputs: [] }) } },
    files: {}
  },
  lockfile_present_but_empty: {
    policy: requirements("unit"),
    workspace: { verifiers: { unit: script({ inputs: [] }) } },
    files: { "/repo/pnpm-lock.yaml": "" }
  },
  lockfile_holds_the_word_absent: {
    policy: requirements("unit"),
    workspace: { verifiers: { unit: script({ inputs: [] }) } },
    files: { "/repo/pnpm-lock.yaml": "absent" }
  },
  custom_lockfile_name: {
    policy: requirements("unit"),
    workspace: { verifiers: { unit: script({ inputs: [] }) } },
    files: { "/repo/package-lock.json": "{}", "/repo/pnpm-lock.yaml": "ignored" },
    lockfile: "package-lock.json"
  },
  empty_lockfile_name_reads_the_root: {
    policy: requirements("unit"),
    workspace: { verifiers: { unit: script({ inputs: [] }) } },
    files: { "/repo": "root as a file" },
    lockfile: ""
  },
  input_present_absent_and_empty: {
    policy: {
      ...requirements("unit"),
      verifiers: { unit: script({ inputs: ["Tests/{slug}.swift", "Tests/missing.swift", "Tests/empty.swift"] }) }
    },
    files: {
      "/repo/Tests/checkout.apply_coupon.swift": "func testCoupon() {}\n",
      "/repo/Tests/empty.swift": "",
      "/repo/pnpm-lock.yaml": "lock"
    }
  },
  inputs_deduped_across_verifiers_and_sorted: {
    policy: {
      mode: "requirements",
      requirements: [{ required_verifiers: ["unit", "ui", "blocked"] }],
      verifiers: {
        unit: script({ inputs: ["b.txt", "a.txt", "b.txt", "B.txt", "\u00e9.txt", "e\u0301.txt"] }),
        ui: script({ inputs: ["a.txt", "_.txt"], command: ["ui"] })
      }
    },
    files: { "/repo/a.txt": "A", "/repo/\u00e9.txt": "precomposed", "/repo/e\u0301.txt": "decomposed" }
  },
  paths_joined_and_normalized: {
    policy: {
      ...requirements("unit"),
      verifiers: {
        unit: script({ inputs: ["./x/../y.txt", "../outside.txt", "dir/", "/abs/../kept.txt", "//double.txt", "a//b.txt"] })
      }
    },
    files: { "/repo/y.txt": "y", "/outside.txt": "o", "/abs/../kept.txt": "verbatim", "/repo/a/b.txt": "ab" }
  },
  relative_root: {
    policy: { ...requirements("unit"), verifiers: { unit: script({ inputs: ["t.txt", "../up.txt"] }) } },
    files: { "repo/t.txt": "t", "up.txt": "up", "repo/pnpm-lock.yaml": "l" },
    root: "repo/"
  },
  empty_root: {
    policy: { ...requirements("unit"), verifiers: { unit: script({ inputs: ["t.txt", ""] }) } },
    files: { "t.txt": "t", "pnpm-lock.yaml": "l", ".": "dot" },
    root: ""
  },
  timeout_is_hashed: {
    policy: { ...requirements("unit"), verifiers: { unit: script({ timeout_seconds: 60 }) } },
    files: {}
  },
  blocked_verifier_is_hashed_with_its_reason: {
    policy: requirements("unit"),
    files: {}
  },
  policy_null: { policy: null, files: {} },
  policy_absent: { files: {} },
  non_ascii_contents: {
    policy: { ...requirements("unit"), verifiers: { unit: script({ inputs: ["t.txt"] }) } },
    files: { "/repo/t.txt": "caf\u00e9 \ud83d\ude00\r\n" }
  },
  preset_fields_not_hashed: {
    policy: { ...requirements("unit"), verifiers: { unit: { preset: "js.vitest", evidence_kind: "x" } } },
    files: {}
  },
  workspace_verifier_hashed: {
    policy: requirements(DEFAULT_CONVENTION_VERIFIER_ID),
    workspace: { default: "unit", verifiers: { unit: script() } },
    files: {}
  }
};

const contextCases = Object.entries(contextInputs).map(([name, entry]) => {
  const fs = fakeFs(entry.files);
  const args = {
    slug: "checkout.apply_coupon",
    rootDir: entry.root ?? "/repo",
    fs
  };
  if (Object.hasOwn(entry, "policy")) {
    args.verificationPolicy = entry.policy;
  }
  if (entry.workspace !== undefined) {
    args.workspaceVerifiers = entry.workspace;
  }
  if (entry.lockfile !== undefined) {
    args.lockfileName = entry.lockfile;
  }
  const contextHash = computeRowVerificationContextHash(args);
  // Every path answers with its own name, so this hash moves if a single path
  // is built differently: it pins WHICH files are read, not just their bytes.
  const probeHash = computeRowVerificationContextHash({ ...args, fs: { readText: (path) => `read:${path}` } });
  return {
    name,
    slug: args.slug,
    root: args.rootDir,
    has_policy: Object.hasOwn(entry, "policy"),
    policy: entry.policy ?? null,
    workspace: entry.workspace ?? null,
    lockfile: entry.lockfile ?? null,
    files: entry.files,
    context_hash: contextHash,
    probe_hash: probeHash,
    reads: fs.reads
  };
});

// The hash over a caller-built verifier list: unsorted, duplicated ids, a
// blocked one and inputs on a blocked one (which are never hashed).
const directVerifierLists = {
  unsorted_with_duplicates: [
    { verifier_id: "z", status: "resolved", source: "policy", kind: "script", evidence_kind: "e", command: ["z"], inputs: ["z.txt"] },
    { verifier_id: "a", status: "blocked", reason: "no verifier" },
    { verifier_id: "a", status: "resolved", source: "workspace_config", kind: "script", evidence_kind: "e", command: [], inputs: ["a.txt"], timeout_seconds: 0, preset: "go.test" }
  ],
  empty: []
};

const directContextCases = Object.entries(directVerifierLists).map(([name, verifiers]) => {
  const files = { "/repo/a.txt": "a", "/repo/pnpm-lock.yaml": "lock" };
  const fs = fakeFs(files);
  return {
    name,
    verifiers,
    policy: { any: "policy" },
    files,
    context_hash: computeVerificationContextHash({
      verificationPolicy: { any: "policy" },
      verifiers,
      rootDir: "/repo",
      fs
    }),
    reads: fs.reads
  };
});

// ---------------------------------------------------------------------------
// freshness
// ---------------------------------------------------------------------------

// Named predicates for policy_mode "custom". The Swift side defines the same set.
const CUSTOM_POLICIES = {
  always_true: () => true,
  always_false: () => false,
  status_is_suspect: (context) => context.status === "SUSPECT",
  required_for_release: (context) => context.required_for_release,
  is_invalid: (context) => context.is_invalid,
  row_is_alpha_b: (context) => context.row_id === "alpha.b"
};

const verificationPolicy = requirements("unit");

function row(rowId, extra = {}) {
  return {
    row_id: rowId,
    title: `Row ${rowId}`,
    verification_policy: verificationPolicy,
    approval_policy: { required_for_release: false },
    ...extra
  };
}

const requiredRow = (rowId, extra = {}) =>
  row(rowId, { approval_policy: { required_for_release: true }, ...extra });

const file = (filePath, ...slugs) => ({
  file_path: filePath,
  contents: slugs.map((slug) => explicitBlock(slug, `value = "${slug}"`)).join("\n")
});

// The current, registered bindings for a row, exactly as deriveFreshness sees
// them, so a proof can be minted against the current state and then bent.
function currentItems(input, rowId, bindingRowId = rowId) {
  const scan = scanFiles(input.files);
  const known = new Set((input.registry.find(([id]) => id === rowId) ?? [rowId, []])[1]);
  return scan.bindings
    .filter((binding) => binding.row_id === rowId && known.has(binding.binding_slug))
    .map((binding) => ({
      binding_slug: binding.binding_slug,
      row_id: bindingRowId,
      file_path: binding.file_path,
      extent_kind: binding.extent_kind,
      recognizer_id: binding.recognizer_id,
      span_canon_id: binding.span_canon_id,
      span_sha256: binding.span.sha256,
      span_start_line: binding.span.start_line,
      span_end_line: binding.span.end_line
    }));
}

function bindingSetHashFor(input, rowId, hashRowId = rowId) {
  return computeBindingSetHash(hashRowId, currentItems(input, rowId));
}

// A passing proof minted against the case's CURRENT state; `bend` then edits it.
function proof(input, rowId, options = {}) {
  const rowValue = input.rows.find((candidate) => candidate.row_id === rowId);
  const items = options.items ?? currentItems(input, rowId);
  const event = {
    schema: "ucase-proof-event-v1",
    event_type: "row_proof_passed",
    event_id: options.event_id ?? `evt_${rowId}`,
    created_at: options.created_at ?? "2026-06-01T12:00:00Z",
    producer: {
      kind: "trusted-ci-prover",
      id: "ucm-ci",
      version: "1.0.0",
      ci_run_id: "run-1",
      repo: "example/app",
      commit: options.commit ?? "abc123"
    },
    row: {
      row_id: rowId,
      row_hash_id: "existing-semantic-row-hash",
      row_hash: rowValue ? computeRowHash(rowValue) : hash("0"),
      verification_policy_hash: rowValue ? computeVerificationPolicyHash(rowValue.verification_policy) : hash("1"),
      approval_policy_hash: rowValue ? computeApprovalPolicyHash(rowValue.approval_policy) : hash("2")
    },
    bindings: {
      binding_set_hash_id: "ucase-binding-set-v1",
      binding_set_hash: computeBindingSetHash(rowId, items),
      span_canon_id: "ucase-span-lines-v2",
      items
    },
    verification: {
      command_id: "swift-test",
      result: "pass",
      started_at: "2026-06-01T11:59:00Z",
      completed_at: "2026-06-01T12:00:00Z",
      artifacts: [],
      context_hash_id: VERIFICATION_CONTEXT_HASH_ID,
      context_hash: options.context_hash ?? hash("c")
    }
  };
  if (options.authority !== undefined) {
    event.authority = options.authority;
  }
  options.bend?.(event);
  return event;
}

const ciAuthority = (protectedRef) => {
  const authority = { type: "ci", provider: "github-actions", repository: "example/app" };
  if (protectedRef !== "omit") {
    authority.protected_ref = protectedRef;
  }
  return authority;
};

const localResult = (rowId, contextHash, bindingSetHash, passed, attested) => {
  const result = { row_id: rowId, context_hash: contextHash, binding_set_hash: bindingSetHash, passed };
  if (attested !== undefined) {
    result.attested = attested;
  }
  return result;
};

// Every case starts from this and overrides what it needs. `evidence`,
// `local_results`, `performed_runs` and `current_context_hashes` may be functions
// of the finished input, so proofs are minted against the case's own state.
const base = () => ({
  rows: [],
  registry: [],
  files: [],
  extra_errors: [],
  evidence: [],
  policy_mode: "feature"
});

// One bound row, `alpha.a`, registered and marked in a.py.
const boundAlpha = (extra = {}) => ({
  ...base(),
  rows: [row("alpha.a")],
  registry: [["alpha.a", ["alpha.a"]]],
  files: [file("a.py", "alpha.a")],
  ...extra
});

const withProof = (options = {}) => (input) => [proof(input, "alpha.a", options)];

const freshnessInputs = {
  // -- the empty matrix and the plain statuses ------------------------------
  empty_matrix: base(),
  unbound_row: { ...base(), rows: [row("alpha.a")] },
  unproven_row: boundAlpha(),
  fresh_row: boundAlpha({ evidence: withProof() }),
  fresh_row_with_injected_tool_and_root: boundAlpha({
    evidence: withProof(),
    tool: { name: "custom-tool", version: "9.9.9" },
    product_root: "/work/app"
  }),
  swift_inferred_binding: {
    ...base(),
    rows: [row("alpha.s")],
    registry: [["alpha.s", ["alpha.s"]]],
    files: [{ file_path: "S.swift", contents: lines(`${markerToken("//")}alpha.s`, "func f() {", "  g()", "}") }],
    evidence: (input) => [proof(input, "alpha.s")]
  },
  multiple_bindings_across_files: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a#z", "alpha.a", "alpha.a#b"]]],
    files: [file("z.py", "alpha.a#z"), file("a.py", "alpha.a", "alpha.a#b")],
    evidence: withProof()
  },

  // -- FRESH match predicate: each conjunct failing on its own ----------------
  stale_row_hash: boundAlpha({ evidence: withProof({ bend: (e) => { e.row.row_hash = hash("9"); } }) }),
  stale_verification_policy_hash: boundAlpha({
    evidence: withProof({ bend: (e) => { e.row.verification_policy_hash = hash("8"); } })
  }),
  stale_approval_policy_hash: boundAlpha({
    evidence: withProof({ bend: (e) => { e.row.approval_policy_hash = hash("7"); } })
  }),
  stale_binding_set_hash_only: boundAlpha({
    evidence: withProof({ bend: (e) => { e.bindings.binding_set_hash = hash("6"); } })
  }),
  unsupported_span_canon_with_matching_set_hash: boundAlpha({
    evidence: (input) => [
      proof(input, "alpha.a", {
        bend: (e) => {
          e.bindings.items = e.bindings.items.map((item) => ({ ...item, span_canon_id: "ucase-span-lines-v1" }));
          e.bindings.binding_set_hash = bindingSetHashFor(input, "alpha.a");
        }
      })
    ]
  }),
  unsupported_span_canon_with_drifted_set_hash: boundAlpha({
    evidence: withProof({
      bend: (e) => {
        e.bindings.items = e.bindings.items.map((item) => ({ ...item, span_canon_id: "ucase-span-lines-v1" }));
        e.bindings.binding_set_hash = computeBindingSetHash("alpha.a", e.bindings.items);
      }
    })
  }),
  context_hash_matches: boundAlpha({
    evidence: withProof({ context_hash: hash("c") }),
    current_context_hashes: [["alpha.a", hash("c")]]
  }),
  context_hash_changed: boundAlpha({
    evidence: withProof({ context_hash: hash("c") }),
    current_context_hashes: [["alpha.a", hash("d")]]
  }),
  context_map_without_the_row: boundAlpha({
    evidence: withProof({ context_hash: hash("c") }),
    current_context_hashes: [["other.row", hash("c")]]
  }),
  context_map_without_the_row_and_proof_without_hash: boundAlpha({
    evidence: withProof({ bend: (e) => { delete e.verification.context_hash; } }),
    current_context_hashes: []
  }),
  proof_without_context_hash_against_a_map: boundAlpha({
    evidence: withProof({ bend: (e) => { delete e.verification.context_hash; } }),
    current_context_hashes: [["alpha.a", hash("c")]]
  }),
  context_map_is_empty_string_for_the_row: boundAlpha({
    evidence: withProof({ context_hash: hash("c") }),
    current_context_hashes: [["alpha.a", ""]]
  }),
  context_map_later_entry_wins: boundAlpha({
    evidence: withProof({ context_hash: hash("c") }),
    current_context_hashes: [["alpha.a", hash("d")], ["alpha.a", hash("c")]]
  }),
  proof_result_not_pass: boundAlpha({
    evidence: withProof({ bend: (e) => { e.verification.result = "fail"; } })
  }),
  trusted_producer_mismatch: {
    ...boundAlpha(),
    rows: [row("alpha.a", { approval_policy: { trusted_producer: "human-review" } })],
    evidence: withProof()
  },
  trusted_producer_matches: {
    ...boundAlpha(),
    rows: [row("alpha.a", { approval_policy: { trusted_producer: "trusted-ci-prover" } })],
    evidence: withProof()
  },
  trusted_producer_not_a_string: {
    ...boundAlpha(),
    rows: [row("alpha.a", { approval_policy: { trusted_producer: 7 } })],
    evidence: withProof()
  },
  approval_policy_null: {
    ...boundAlpha(),
    rows: [row("alpha.a", { approval_policy: null })],
    evidence: withProof()
  },
  approval_policy_is_an_array: {
    ...boundAlpha(),
    rows: [row("alpha.a", { approval_policy: [{ required_for_release: true }] })],
    evidence: withProof()
  },
  required_for_release_truthy_but_not_true: {
    ...boundAlpha(),
    rows: [row("alpha.a", { approval_policy: { required_for_release: "yes" } })],
    policy_mode: "release"
  },

  // -- stale reasons ---------------------------------------------------------
  code_span_changed: boundAlpha({
    evidence: withProof({
      bend: (e) => {
        e.bindings.items = e.bindings.items.map((item) => ({ ...item, span_sha256: hash("5") }));
        e.bindings.binding_set_hash = computeBindingSetHash("alpha.a", e.bindings.items);
      }
    })
  }),
  binding_path_changed: boundAlpha({
    evidence: withProof({
      bend: (e) => {
        e.bindings.items = e.bindings.items.map((item) => ({ ...item, file_path: "old/a.py" }));
        e.bindings.binding_set_hash = computeBindingSetHash("alpha.a", e.bindings.items);
      }
    })
  }),
  every_per_binding_reason_at_once: boundAlpha({
    evidence: withProof({
      bend: (e) => {
        e.bindings.items = e.bindings.items.map((item) => ({
          ...item,
          file_path: "old/a.py",
          span_sha256: hash("5"),
          span_canon_id: "ucase-span-lines-v1"
        }));
        e.row.row_hash = hash("9");
        e.row.verification_policy_hash = hash("8");
        e.row.approval_policy_hash = hash("7");
      }
    }),
    current_context_hashes: [["alpha.a", hash("d")]]
  }),
  binding_added_since_proof: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a", "alpha.a#new"]]],
    files: [file("a.py", "alpha.a", "alpha.a#new")],
    evidence: (input) => [
      proof(input, "alpha.a", { items: currentItems(input, "alpha.a").filter((item) => item.binding_slug === "alpha.a") })
    ]
  },
  binding_in_proof_no_longer_current: boundAlpha({
    evidence: (input) => [
      proof(input, "alpha.a", {
        items: [
          ...currentItems(input, "alpha.a"),
          { ...currentItems(input, "alpha.a")[0], binding_slug: "alpha.a#gone" }
        ]
      })
    ]
  }),
  set_hash_drift_reported_beside_row_drift: boundAlpha({
    evidence: withProof({
      bend: (e) => {
        e.row.row_hash = hash("9");
        e.bindings.binding_set_hash = hash("6");
      }
    })
  }),
  equivalent_binding_slugs_in_proof_stay_distinct: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a"]]],
    files: [file("a.py", "alpha.a")],
    evidence: (input) => [
      proof(input, "alpha.a", {
        bend: (e) => {
          e.bindings.items = [
            ...e.bindings.items,
            { ...e.bindings.items[0], binding_slug: "alpha.a#caf\u00e9" },
            { ...e.bindings.items[0], binding_slug: "alpha.a#cafe\u0301" }
          ];
          e.bindings.binding_set_hash = computeBindingSetHash("alpha.a", e.bindings.items);
        }
      })
    ]
  },
  proof_item_path_differs_only_by_normalization: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a"]]],
    files: [file("caf\u00e9.py", "alpha.a")],
    evidence: withProof({
      bend: (e) => {
        e.bindings.items = e.bindings.items.map((item) => ({ ...item, file_path: "cafe\u0301.py" }));
        e.bindings.binding_set_hash = computeBindingSetHash("alpha.a", e.bindings.items);
      }
    })
  },

  // -- proof ordering --------------------------------------------------------
  newest_matching_proof_wins: boundAlpha({
    evidence: (input) => [
      proof(input, "alpha.a", { event_id: "evt_old", created_at: "2026-06-01T10:00:00Z", commit: "old" }),
      proof(input, "alpha.a", { event_id: "evt_new", created_at: "2026-06-02T10:00:00Z", commit: "new" }),
      proof(input, "alpha.a", { event_id: "evt_mid", created_at: "2026-06-01T11:00:00Z", commit: "mid" })
    ]
  }),
  older_proof_matches_newer_is_stale: boundAlpha({
    evidence: (input) => [
      proof(input, "alpha.a", { event_id: "evt_good", created_at: "2026-06-01T10:00:00Z" }),
      proof(input, "alpha.a", {
        event_id: "evt_stale",
        created_at: "2026-06-03T10:00:00Z",
        bend: (e) => { e.row.row_hash = hash("9"); }
      })
    ]
  }),
  equal_timestamps_keep_ledger_order: boundAlpha({
    evidence: (input) => [
      proof(input, "alpha.a", { event_id: "evt_first", commit: "first" }),
      proof(input, "alpha.a", { event_id: "evt_second", commit: "second" })
    ]
  }),
  newest_stale_proof_explains_the_drift: boundAlpha({
    evidence: (input) => [
      proof(input, "alpha.a", { event_id: "evt_row", created_at: "2026-06-01T10:00:00Z", bend: (e) => { e.row.row_hash = hash("9"); } }),
      proof(input, "alpha.a", { event_id: "evt_result", created_at: "2026-06-02T10:00:00Z", bend: (e) => { e.verification.result = "fail"; } })
    ]
  }),
  proof_for_another_row_is_ignored: {
    ...boundAlpha(),
    rows: [row("alpha.a"), row("beta.b")],
    evidence: (input) => [proof(input, "beta.b", { items: currentItems(input, "alpha.a") })]
  },

  // -- removed bindings ------------------------------------------------------
  one_registered_binding_removed: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a", "alpha.a#gone", "alpha.a#also_gone"]]],
    files: [file("a.py", "alpha.a")],
    evidence: withProof()
  },
  all_registered_bindings_removed: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a#b", "alpha.a"]]],
    files: []
  },

  // -- INVALID ---------------------------------------------------------------
  unregistered_marker: { ...base(), rows: [row("alpha.a")], files: [file("a.py", "alpha.a")] },
  unregistered_marker_beside_registered_one: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a"]]],
    files: [file("a.py", "alpha.a", "alpha.a#extra")],
    evidence: withProof(),
    local_results: [],
    performed_runs: [{ row_id: "alpha.a" }]
  },
  marker_registered_to_another_row: {
    ...base(),
    rows: [row("alpha.a"), row("beta.b")],
    registry: [["beta.b", ["alpha.a"]]],
    files: [file("a.py", "alpha.a")]
  },
  scan_errors_with_slugs: {
    ...base(),
    rows: [row("alpha.b"), row("alpha.d"), row("alpha.e")],
    registry: [["alpha.d", ["alpha.d"]]],
    files: [
      { file_path: "b.py", contents: lines(`${markerToken("#")}alpha.b#one`, "x = 1") },
      file("d.py", "alpha.d", "alpha.d"),
      { file_path: "e.py", contents: `${markerToken("#")}end alpha.e` }
    ],
    local_results: []
  },
  scan_error_with_malformed_slug_becomes_a_row: {
    ...base(),
    files: [{ file_path: "c.py", contents: explicitBlock("Caf\u00e9") }]
  },
  scan_error_without_slug_is_global: {
    ...base(),
    rows: [row("alpha.a")],
    files: [{ file_path: "x.py", contents: lines(markerToken("#"), "x = 1") }]
  },
  forbidden_payload_names_its_row: {
    ...boundAlpha(),
    files: [
      file("a.py", "alpha.a"),
      { file_path: "f.py", contents: lines(`${markerToken("#")}alpha.a extra`, "x = 1") }
    ],
    evidence: withProof()
  },
  hand_built_errors_empty_and_equivalent_slugs: {
    ...base(),
    rows: [row("alpha.a")],
    extra_errors: [
      { code: "MALFORMED_MARKER", message: "", file_path: "q.py", line: 3, slug: "" },
      { code: "MALFORMED_MARKER", message: "precomposed", file_path: "q.py", line: 4, slug: "caf\u00e9" },
      { code: "MALFORMED_MARKER", message: "decomposed", file_path: "q.py", line: 5, slug: "cafe\u0301" },
      { code: "NESTED_SPAN", message: "last plane", file_path: "q.py", line: 6, slug: "\uffff" },
      { code: "NESTED_SPAN", message: "astral", file_path: "q.py", line: 7, slug: "\ud83d\ude00" },
      { code: "END_WITHOUT_START", message: "suffix", file_path: "q.py", line: 8, slug: "alpha.a#x" },
      { code: "UNBALANCED_IGNORE", message: "no slug", file_path: "q.py", line: 9 }
    ]
  },
  registry_row_not_in_matrix: {
    ...base(),
    registry: [["ghost.row", ["ghost.row"]]],
    files: [file("g.py", "ghost.row")],
    evidence: (input) => [proof(input, "ghost.row")],
    local_results: [],
    performed_runs: [{ row_id: "ghost.row" }]
  },
  duplicate_rows_last_wins: {
    ...boundAlpha(),
    rows: [row("alpha.a", { title: "first" }), row("alpha.a", { title: "second" })],
    evidence: (input) => [proof(input, "alpha.a")]
  },

  // -- renames ---------------------------------------------------------------
  rename_via_missing_marker: {
    ...base(),
    rows: [row("checkout.apply_coupon")],
    registry: [["checkout.apply_coupon", ["checkout.apply_coupon"]]],
    files: [file("c.py", "checkout.apply_coupons")]
  },
  rename_via_registry_row_missing: {
    ...base(),
    rows: [row("mcp.stage")],
    files: [file("m.py", "mcp.stage_whiteboard")],
    global_integrity_errors: [
      {
        code: "REGISTRY_ROW_MISSING",
        line: 1,
        message: "registry binds a row not in the matrix",
        binding_slug: "mcp.whiteboard",
        row_id: "mcp.whiteboard"
      }
    ]
  },
  rename_same_row_by_both_routes_is_not_ambiguous: {
    ...base(),
    rows: [row("orders.refund_item")],
    registry: [["orders.refund_item", ["orders.refund_item"]]],
    files: [file("o.py", "orders.refund_items")],
    global_integrity_errors: [
      { code: "REGISTRY_ROW_MISSING", message: "stale", binding_slug: "orders.refund_item", row_id: "orders.refund_item" }
    ]
  },
  rename_tie_is_refused: {
    ...base(),
    rows: [row("abcd.x1"), row("abcd.x2")],
    registry: [["abcd.x1", ["abcd.x1"]], ["abcd.x2", ["abcd.x2"]]],
    files: [file("n.py", "abcd.x")]
  },
  rename_below_threshold_is_silent: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a"]]],
    files: [file("z.py", "zulu.q")]
  },
  rename_best_candidate_wins: {
    ...base(),
    rows: [row("billing.invoice_send"), row("billing.invoice_sent_mail")],
    registry: [["billing.invoice_send", ["billing.invoice_send"]], ["billing.invoice_sent_mail", ["billing.invoice_sent_mail"]]],
    files: [file("b.py", "billing.invoice_sends")]
  },
  renamed_to_last_detection_wins: {
    ...base(),
    rows: [],
    files: [file("r.py", "shop.cart_item_a", "shop.cart_item_b")],
    global_integrity_errors: [
      { code: "REGISTRY_ROW_MISSING", message: "stale", binding_slug: "shop.cart_item", row_id: "shop.cart_item" }
    ]
  },
  rename_to_the_same_row_scores_exactly_one: {
    ...base(),
    rows: [row("alpha.a")],
    registry: [["alpha.a", ["alpha.a#old"]]],
    files: [file("a.py", "alpha.a#new")]
  },
  short_row_ids_have_no_bigrams: {
    ...base(),
    rows: [row("a")],
    registry: [["a", ["a"]]],
    files: [file("s.py", "b")]
  },
  non_ascii_rename_candidates_use_code_units: {
    ...base(),
    rows: [],
    files: [file("u.py", "abcdefgh")],
    global_integrity_errors: [
      { code: "REGISTRY_ROW_MISSING", message: "astral", row_id: "abcdefg\ud83d\ude00" },
      { code: "REGISTRY_ROW_MISSING", message: "precomposed", row_id: "abcdefgh\u00e9" }
    ]
  },

  // -- global integrity errors and their remediation -------------------------
  global_errors_every_remediation_route: {
    ...boundAlpha(),
    evidence: withProof(),
    global_integrity_errors: [
      { message: "ledger line out of order", event_id: "evt_1" },
      { code: "BAD_SIGNATURE", line: 4, message: "signature does not verify", event_id: "evt_2" },
      { code: "REGISTRY_ROW_MISSING", message: "no row", binding_slug: "old.row", row_id: "old.row" },
      { code: "REGISTRY_ROW_MISSING", message: "no row id" },
      { code: "REGISTRY_ROW_MISSING", message: "null row id", row_id: null },
      { code: "REGISTRY_ROW_MISSING", message: "zero row id", row_id: 0 },
      { code: "REGISTRY_ROW_MISSING", message: "numeric row id", row_id: 12.5 },
      { code: "REGISTRY_ROW_MISSING", message: "array row id", row_id: ["x", null, 1] },
      { code: "REGISTRY_ROW_MISSING", message: "object row id", row_id: { nested: true } },
      { code: "REGISTRY_ROW_MISSING", message: "empty row id", row_id: "" },
      { code: "REGISTRY_ROW_MISSING", message: "kept", row_id: "keep.row", remediation: "already told" },
      { code: "REGISTRY_ROW_MISSING", message: "falsy remediation", row_id: "keep.row", remediation: "", extra: 1 },
      { remediation: 0, message: "zero remediation" },
      { code: null, message: "null code" },
      { code: "LEDGER_INTEGRITY_ERROR", message: "explicit ledger code" }
    ]
  },
  global_error_key_order_is_the_callers: {
    ...base(),
    global_integrity_errors: [
      { line: 2, message: "m", code: "CHAIN_BROKEN", "\u00e9": 1, "e\u0301": 2, nested: { b: 1, a: [null, true] } }
    ]
  },

  // -- policy modes ----------------------------------------------------------
  feature_mode_blocks_only_invalid: {
    ...base(),
    rows: [requiredRow("alpha.a"), requiredRow("alpha.b"), row("alpha.c")],
    registry: [["alpha.a", ["alpha.a"]], ["alpha.c", ["alpha.c"]]],
    files: [file("a.py", "alpha.a"), file("c.py", "alpha.c", "alpha.c#stray")],
    policy_mode: "feature"
  },
  release_mode_blocks_required_not_fresh: {
    ...base(),
    rows: [requiredRow("alpha.a"), requiredRow("alpha.b"), row("alpha.c"), requiredRow("alpha.d"), row("alpha.e")],
    registry: [["alpha.a", ["alpha.a"]], ["alpha.b", ["alpha.b"]], ["alpha.c", ["alpha.c"]], ["alpha.e", ["alpha.e"]]],
    files: [file("a.py", "alpha.a"), file("b.py", "alpha.b"), file("c.py", "alpha.c"), file("e.py", "alpha.e", "alpha.e#x")],
    evidence: (input) => [proof(input, "alpha.a")],
    policy_mode: "release"
  },
  custom_mode_without_predicate_blocks_invalid: {
    ...base(),
    rows: [requiredRow("alpha.a"), row("alpha.b")],
    registry: [["alpha.a", ["alpha.a"]]],
    files: [file("a.py", "alpha.a"), file("b.py", "alpha.b")],
    policy_mode: "custom"
  },
  ...Object.fromEntries(
    Object.keys(CUSTOM_POLICIES).map((name) => [
      `custom_mode_${name}`,
      {
        ...base(),
        rows: [requiredRow("alpha.a"), row("alpha.b"), requiredRow("alpha.c"), row("alpha.d")],
        registry: [["alpha.a", ["alpha.a"]], ["alpha.b", ["alpha.b"]], ["alpha.c", ["alpha.c"]]],
        files: [file("a.py", "alpha.a"), file("b.py", "alpha.b"), file("c.py", "alpha.c"), file("d.py", "alpha.d")],
        evidence: (input) => [proof(input, "alpha.a"), proof(input, "alpha.b", { bend: (e) => { e.row.row_hash = hash("9"); } })],
        policy_mode: "custom",
        custom_policy: name,
        release_gate: { required_authority: "ci" }
      }
    ])
  ),
  ...Object.fromEntries(
    ["feature", "release"].map((mode) => [
      `${mode}_mode_ignores_a_custom_predicate`,
      {
        ...base(),
        rows: [requiredRow("alpha.a"), row("alpha.b")],
        registry: [["alpha.a", ["alpha.a"]], ["alpha.b", ["alpha.b"]]],
        files: [file("a.py", "alpha.a"), file("b.py", "alpha.b")],
        policy_mode: mode,
        custom_policy: "always_true"
      }
    ])
  ),

  // -- release gate authority ------------------------------------------------
  ...Object.fromEntries(
    [
      ["gate_ci_no_authority_block", { required_authority: "ci" }, undefined],
      ["gate_ci_local_authority", { required_authority: "ci" }, { type: "local", provider: "generic" }],
      ["gate_ci_ci_authority", { required_authority: "ci" }, ciAuthority("omit")],
      ["gate_ci_authority_type_unexpected", { required_authority: "ci" }, { type: 7, provider: "x" }],
      ["gate_protected_true", { require_protected_ref: true }, ciAuthority(true)],
      ["gate_protected_false", { require_protected_ref: true }, ciAuthority(false)],
      ["gate_protected_null", { require_protected_ref: true }, ciAuthority(null)],
      ["gate_protected_omitted", { require_protected_ref: true }, ciAuthority("omit")],
      ["gate_protected_no_authority_block", { require_protected_ref: true }, undefined],
      ["gate_protected_string_true", { require_protected_ref: true }, { ...ciAuthority("omit"), protected_ref: "true" }],
      ["gate_both_satisfied", { required_authority: "ci", require_protected_ref: true }, ciAuthority(true)],
      ["gate_both_local_unprotected", { required_authority: "ci", require_protected_ref: true }, { type: "local", provider: "generic", protected_ref: false }],
      ["gate_both_ci_unprotected", { required_authority: "ci", require_protected_ref: true }, ciAuthority(null)],
      ["gate_both_no_authority_block", { required_authority: "ci", require_protected_ref: true }, undefined],
      ["gate_empty_object", {}, undefined],
      ["gate_all_falsy", { required_authority: "github", require_protected_ref: false }, undefined],
      ["gate_protected_truthy_not_true", { require_protected_ref: "yes" }, undefined],
      ["gate_null_authority_block", { required_authority: "ci" }, null]
    ].map(([name, gate, authority]) => [
      `release_${name}`,
      {
        ...base(),
        rows: [requiredRow("alpha.a"), row("alpha.b")],
        registry: [["alpha.a", ["alpha.a"]], ["alpha.b", ["alpha.b"]]],
        files: [file("a.py", "alpha.a"), file("b.py", "alpha.b")],
        evidence: (input) => [
          proof(input, "alpha.a", { authority }),
          proof(input, "alpha.b", { authority })
        ],
        policy_mode: "release",
        release_gate: gate
      }
    ])
  ),
  release_gate_uses_the_matching_proof_not_the_latest: {
    ...base(),
    rows: [requiredRow("alpha.a")],
    registry: [["alpha.a", ["alpha.a"]]],
    files: [file("a.py", "alpha.a")],
    evidence: (input) => [
      proof(input, "alpha.a", { event_id: "evt_match", created_at: "2026-06-01T10:00:00Z", authority: { type: "local", provider: "generic" } }),
      proof(input, "alpha.a", { event_id: "evt_newer_stale", created_at: "2026-06-05T10:00:00Z", authority: ciAuthority(true), bend: (e) => { e.row.row_hash = hash("9"); } })
    ],
    policy_mode: "release",
    release_gate: { required_authority: "ci" }
  },
  release_gate_in_feature_mode_is_ignored: {
    ...base(),
    rows: [requiredRow("alpha.a")],
    registry: [["alpha.a", ["alpha.a"]]],
    files: [file("a.py", "alpha.a")],
    evidence: (input) => [proof(input, "alpha.a")],
    policy_mode: "feature",
    release_gate: { required_authority: "ci", require_protected_ref: true }
  },
  release_gate_on_a_required_row_that_is_not_fresh: {
    ...base(),
    rows: [requiredRow("alpha.a")],
    registry: [["alpha.a", ["alpha.a"]]],
    files: [file("a.py", "alpha.a")],
    policy_mode: "release",
    release_gate: { required_authority: "ci" }
  },

  // -- keyless local tier ----------------------------------------------------
  local_results_across_every_status: {
    ...base(),
    rows: [row("alpha.a"), row("alpha.b"), row("alpha.c"), row("alpha.u")],
    registry: [["alpha.a", ["alpha.a"]], ["alpha.b", ["alpha.b"]], ["alpha.c", ["alpha.c"]]],
    files: [file("a.py", "alpha.a"), file("b.py", "alpha.b"), file("c.py", "alpha.c", "alpha.c#stray")],
    evidence: (input) => [proof(input, "alpha.a")],
    local_results: []
  },
  ...Object.fromEntries(
    [
      ["verified_attested", (bind) => [localResult("alpha.a", hash("c"), bind, true, true)], true],
      ["verified_attestation_unmodelled", (bind) => [localResult("alpha.a", hash("x"), bind, true)], false],
      ["verified_without_context_map", (bind) => [localResult("alpha.a", hash("x"), bind, true, true)], false],
      ["unattested_only", (bind) => [localResult("alpha.a", hash("c"), bind, true, false), localResult("alpha.a", hash("c"), bind, false, false)], true],
      ["forged_beside_honest", (bind) => [localResult("alpha.a", hash("c"), bind, true, false), localResult("alpha.a", hash("c"), bind, true, true)], true],
      ["context_drifted", (bind) => [localResult("alpha.a", hash("old"), bind, true, true)], true],
      ["binding_drifted", (bind) => [localResult("alpha.a", hash("c"), hash("b"), true, true)], true],
      ["context_and_binding_drifted", (bind) => [localResult("alpha.a", hash("old"), hash("b"), true, true)], true],
      ["failed", (bind) => [localResult("alpha.a", hash("c"), bind, false, true)], true],
      ["failed_and_binding_drifted", (bind) => [localResult("alpha.a", hash("c"), bind, false, true), localResult("alpha.a", hash("c"), hash("b"), true)], true],
      ["failure_drift_is_not_context_drift", (bind) => [localResult("alpha.a", hash("old"), hash("b"), false, true)], true],
      ["context_drift_without_map_is_binding_drift", (bind) => [localResult("alpha.a", hash("old"), hash("b"), true, true)], false],
      ["result_for_another_row", (bind) => [localResult("alpha.b", hash("c"), bind, true, true)], true]
    ].map(([name, results, withContext]) => [
      `local_${name}`,
      boundAlpha({
        local_results: (input) => results(bindingSetHashFor(input, "alpha.a")),
        ...(withContext ? { current_context_hashes: [["alpha.a", hash("c")]] } : {})
      })
    ])
  ),
  local_fresh_row_is_verified_by_its_proof: boundAlpha({
    evidence: withProof(),
    local_results: (input) => [localResult("alpha.a", hash("c"), hash("b"), false, false)]
  }),
  local_results_omitted_emit_nothing: boundAlpha({ evidence: withProof() }),

  // -- variant families ------------------------------------------------------
  ...Object.fromEntries(
    [
      ["all_verified", (input) => ["a", "b"].map((key) => localResult(`fam.row::${key}`, hash("c"), bindingSetHashFor(input, "fam.row", `fam.row::${key}`), true, true))],
      ["one_stale", (input) => [
        localResult("fam.row::a", hash("c"), bindingSetHashFor(input, "fam.row", "fam.row::a"), true, true),
        localResult("fam.row::b", hash("old"), bindingSetHashFor(input, "fam.row", "fam.row::b"), true, true)
      ]],
      ["one_unverified", (input) => [
        localResult("fam.row::b", hash("c"), bindingSetHashFor(input, "fam.row", "fam.row::b"), true, true)
      ]],
      ["unattested_outranks_stale", (input) => [
        localResult("fam.row::a", hash("c"), bindingSetHashFor(input, "fam.row", "fam.row::a"), true, false),
        localResult("fam.row::b", hash("c"), hash("x"), true, true)
      ]],
      ["family_id_result_is_ignored", (input) => [
        localResult("fam.row", hash("c"), bindingSetHashFor(input, "fam.row"), true, true)
      ]],
      ["variant_hash_is_not_the_family_hash", (input) => ["a", "b"].map((key) => localResult(`fam.row::${key}`, hash("c"), bindingSetHashFor(input, "fam.row"), true, true))]
    ].map(([name, results]) => [
      `variants_${name}`,
      {
        ...base(),
        rows: [row("fam.row", { variants: [{ key: "b", title: "B" }, { key: "a" }] })],
        registry: [["fam.row", ["fam.row"]]],
        files: [file("f.py", "fam.row")],
        local_results: results,
        current_context_hashes: [["fam.row", hash("c")]]
      }
    ])
  ),
  variants_fresh_family_short_circuits: {
    ...base(),
    rows: [row("fam.row", { variants: [{ key: "a" }] })],
    registry: [["fam.row", ["fam.row"]]],
    files: [file("f.py", "fam.row")],
    evidence: (input) => [proof(input, "fam.row")],
    local_results: []
  },
  variants_unbound_family_is_null: {
    ...base(),
    rows: [row("fam.row", { variants: [{ key: "a" }] })],
    local_results: []
  },
  variants_empty_list_is_an_ordinary_row: {
    ...base(),
    rows: [row("fam.row", { variants: [] })],
    registry: [["fam.row", ["fam.row"]]],
    files: [file("f.py", "fam.row")],
    local_results: (input) => [localResult("fam.row", hash("c"), bindingSetHashFor(input, "fam.row"), true, true)]
  },
  variants_not_a_list_is_an_ordinary_row: {
    ...base(),
    rows: [row("fam.row", { variants: { key: "a" } })],
    registry: [["fam.row", ["fam.row"]]],
    files: [file("f.py", "fam.row")],
    local_results: []
  },
  variants_keys_sorted_by_code_unit: {
    ...base(),
    rows: [row("fam.row", { variants: [{ key: "b" }, { key: "B" }, { key: "a_b" }, { key: "a-b" }, { key: "\u00e9" }] })],
    registry: [["fam.row", ["fam.row"]]],
    files: [file("f.py", "fam.row")],
    local_results: []
  },
  variants_duplicate_keys: {
    ...base(),
    rows: [row("fam.row", { variants: [{ key: "b" }, { key: "a" }, { key: "b" }] })],
    registry: [["fam.row", ["fam.row"]]],
    files: [file("f.py", "fam.row")],
    local_results: (input) => [localResult("fam.row::b", hash("c"), bindingSetHashFor(input, "fam.row", "fam.row::b"), true, true)]
  },
  variants_without_local_results: {
    ...base(),
    rows: [row("fam.row", { variants: [{ key: "a" }] })],
    registry: [["fam.row", ["fam.row"]]],
    files: [file("f.py", "fam.row")]
  },

  // -- performed runs and the acceptance claim -------------------------------
  performed_runs_bound_unbound_and_invalid: {
    ...base(),
    rows: [row("alpha.a"), row("alpha.b"), row("alpha.c"), row("alpha.u")],
    registry: [["alpha.a", ["alpha.a"]], ["alpha.b", ["alpha.b"]], ["alpha.c", ["alpha.c"]]],
    files: [file("a.py", "alpha.a"), file("b.py", "alpha.b"), file("c.py", "alpha.c", "alpha.c#stray")],
    performed_runs: [{ row_id: "alpha.a", argv: ["uc", "run"] }, { row_id: "alpha.u" }, { row_id: "alpha.c" }, { row_id: "ghost" }]
  },
  performed_runs_empty: boundAlpha({ performed_runs: [] }),
  acceptance_claimable_by_every_tier: {
    ...base(),
    rows: [row("alpha.a"), row("alpha.b"), row("alpha.c"), row("alpha.d")],
    registry: [["alpha.a", ["alpha.a"]], ["alpha.b", ["alpha.b"]], ["alpha.c", ["alpha.c"]], ["alpha.d", ["alpha.d"]]],
    files: [file("a.py", "alpha.a"), file("b.py", "alpha.b"), file("c.py", "alpha.c"), file("d.py", "alpha.d")],
    evidence: (input) => [proof(input, "alpha.a")],
    local_results: (input) => [
      localResult("alpha.b", hash("x"), bindingSetHashFor(input, "alpha.b"), true, true),
      localResult("alpha.d", hash("x"), bindingSetHashFor(input, "alpha.d"), true, true)
    ],
    performed_runs: [{ row_id: "alpha.a" }, { row_id: "alpha.c" }, { row_id: "alpha.d" }]
  },
  acceptance_with_unattested_rows: {
    ...base(),
    rows: [row("alpha.a"), row("alpha.b")],
    registry: [["alpha.a", ["alpha.a"]], ["alpha.b", ["alpha.b"]]],
    files: [file("a.py", "alpha.a"), file("b.py", "alpha.b")],
    local_results: (input) => [
      localResult("alpha.a", hash("x"), bindingSetHashFor(input, "alpha.a"), true, false),
      localResult("alpha.b", hash("x"), bindingSetHashFor(input, "alpha.b"), true, true)
    ]
  },
  acceptance_blocked_by_global_error: {
    ...boundAlpha({ evidence: withProof() }),
    global_integrity_errors: [{ code: "CHAIN_BROKEN", message: "broken" }]
  },
  acceptance_blocked_by_unbound_row: {
    ...boundAlpha({ evidence: withProof() }),
    rows: [row("alpha.a"), row("alpha.z")]
  },

  // -- the row set -----------------------------------------------------------
  row_ids_sorted_by_code_unit: {
    ...base(),
    rows: [row("b_row"), row("b.row"), row("a-row"), row("a_row"), row("a.row"), row("B")],
    registry: [["b.row", ["b.row#z"]]],
    files: [file("z.py", "b.row#z")]
  }
};

const materialize = (value, input) => (typeof value === "function" ? value(input) : value);

const freshnessCases = Object.entries(freshnessInputs).map(([name, raw]) => {
  const input = { ...raw };
  input.evidence = materialize(raw.evidence, input);
  input.local_results = materialize(raw.local_results, input);
  const registry = {
    rowToSlugs: new Map(input.registry.map(([rowId, slugs]) => [rowId, new Set(slugs)])),
    slugToRow: new Map(input.registry.flatMap(([rowId, slugs]) => slugs.map((slug) => [slug, rowId])))
  };
  const scanned = scanFiles(input.files);
  const scan = { ...scanned, errors: [...scanned.errors, ...input.extra_errors] };
  const call = {
    rows: input.rows,
    registry,
    scan,
    evidence: input.evidence,
    policy_mode: input.policy_mode,
    generated_at: "2026-06-10T09:00:00.000Z"
  };
  if (input.custom_policy !== undefined) {
    call.custom_policy = CUSTOM_POLICIES[input.custom_policy];
  }
  if (input.release_gate !== undefined) {
    call.release_gate = input.release_gate;
  }
  if (input.current_context_hashes !== undefined) {
    call.current_context_hashes = new Map(input.current_context_hashes);
  }
  if (input.local_results !== undefined) {
    call.local_results = input.local_results;
  }
  if (input.performed_runs !== undefined) {
    call.performed_runs = input.performed_runs;
  }
  if (input.global_integrity_errors !== undefined) {
    call.global_integrity_errors = input.global_integrity_errors;
  }
  if (input.tool !== undefined) {
    call.tool = input.tool;
  }
  if (input.product_root !== undefined) {
    call.product_root = input.product_root;
  }
  const entry = {
    name,
    rows: input.rows,
    registry: input.registry,
    files: input.files,
    extra_errors: input.extra_errors,
    evidence: input.evidence,
    policy_mode: input.policy_mode,
    generated_at: call.generated_at,
    wire: JSON.stringify(deriveFreshness(call))
  };
  for (const key of [
    "custom_policy",
    "release_gate",
    "current_context_hashes",
    "local_results",
    "performed_runs",
    "global_integrity_errors",
    "tool",
    "product_root"
  ]) {
    if (input[key] !== undefined) {
      entry[key] = input[key];
    }
  }
  return entry;
});

// The three lockfile answers must differ, or `absent` would collide with a hash.
{
  const byName = Object.fromEntries(contextCases.map((entry) => [entry.name, entry.context_hash]));
  const trio = new Set([byName.lockfile_present, byName.lockfile_absent, byName.lockfile_present_but_empty]);
  if (trio.size !== 3) {
    throw new Error("present, absent and empty lockfiles did not give three different hashes");
  }
}

// ---------------------------------------------------------------------------
// emit
// ---------------------------------------------------------------------------

const corpus = {
  preset_ids: VERIFIER_PRESET_IDS,
  default_convention_verifier_id: DEFAULT_CONVENTION_VERIFIER_ID,
  verification_context_hash_id: VERIFICATION_CONTEXT_HASH_ID,
  presets: presetCases,
  test_suite_presets: testSuitePresetCases,
  resolver: resolverCases,
  context_hash: contextCases,
  context_hash_direct: directContextCases,
  freshness: freshnessCases
};

// Every non-ASCII code unit (including each half of a surrogate pair) becomes
// a \uXXXX escape, so the emitted Swift file is pure ASCII.
const asciiJson = JSON.stringify(corpus).replace(
  /[\u007f-\uffff]/g,
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
// Generated from the TypeScript marker code. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/markers returned for the input
// beside it. The freshness object is the \`use-cases scan\` contract and the context hash
// is embedded in proofs already in ledgers, so these bytes are frozen contract
// (ADR 0007 decision 8).
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-markers-freshness-corpus.mjs
enum MarkersFreshnessGoldenCorpus {
${nameList("presetCaseNames", presetCases)}
${nameList("resolverCaseNames", resolverCases)}
${nameList("contextHashCaseNames", contextCases)}
${nameList("freshnessCaseNames", freshnessCases)}
  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${asciiJson}
  """${pounds}
}

// swiftlint:enable single_line_closure_body line_length
`;

writeFileSync(targetPath, swift);
const written = readFileSync(targetPath, "utf8");
if (!/^[\x00-\x7f]*$/.test(written)) {
  throw new Error("corpus file is not ASCII");
}
console.log(
  `wrote ${targetPath}: ${presetCases.length} preset, ${resolverCases.length} resolver, ` +
    `${contextCases.length + directContextCases.length} context-hash, ${freshnessCases.length} freshness cases`
);
