// Regenerates the presentation planning corpus by running every case below
// through the REAL TypeScript in `packages/core/dist/presentation` against REAL
// temporary directories, and recording exactly what it returns or throws.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-presentation-corpus.mjs
//
// One file is written:
//
//   Tests/UseCasesCoreTests/Presentation/PresentationGoldenCorpus.swift
//     plan cases (a tree loaded by the real matrix loader, or rows handed to
//     `buildMatrixSnapshot`, then evidence replayed, then `selectShowcasePlan`
//     or `selectWalkthroughPlan`), every plan's schema validation, the card
//     rendered for every selected item, hand-built card cases, and the helper
//     probes (plan ids, path order, exclusion wording, plan hashes, formats).
//
// The TypeScript is the oracle (ADR 0007 decision 8). The script refuses to
// run against a `dist` older than its `src`.
//
// Inputs whose key ORDER matters travel as JSON the Swift side parses in
// document order, and the corpus is emitted ASCII-only. Absolute paths are
// replaced by `<workspace>`. `Date` is replaced before the core is imported so
// the one plan case that reads the clock reads a fixed instant.
import { createHash } from "node:crypto";
import {
  chmodSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const coreRoot = join(repositoryRoot, "packages/core");
const testsDirectory = join(packageRoot, "Tests/UseCasesCoreTests/Presentation");

const PORTED = [
  "types",
  "items",
  "renderCard",
  "selectPlan",
  "candidates",
  "scoring",
  "presentationFormat",
  "planHelpers",
  "snapshot",
  "ordering",
  "selection",
  "selectShowcasePlan",
  "selectWalkthroughPlan"
];

for (const name of PORTED) {
  const source = statSync(join(coreRoot, "src/presentation", `${name}.ts`)).mtimeMs;
  const built = statSync(join(coreRoot, "dist/presentation", `${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`dist/presentation/${name}.js is older than src; rebuild packages/core first`);
  }
}

// ---------------------------------------------------------------------------
// The clock: fixed while a case asks for it, real otherwise
// ---------------------------------------------------------------------------

const RealDate = Date;
let clockMilliseconds = null;
class ControlledDate extends RealDate {
  constructor(...args) {
    if (args.length === 0) {
      super(clockMilliseconds === null ? RealDate.now() : clockMilliseconds);
    } else {
      super(...args);
    }
  }
  static now() {
    return clockMilliseconds === null ? RealDate.now() : clockMilliseconds;
  }
}
globalThis.Date = ControlledDate;

const core = await import(join(coreRoot, "dist/index.js"));
const candidatesModule = await import(join(coreRoot, "dist/presentation/candidates.js"));
const snapshotModule = await import(join(coreRoot, "dist/presentation/snapshot.js"));
const helpersModule = await import(join(coreRoot, "dist/presentation/planHelpers.js"));
const {
  buildMatrixSnapshot,
  choosePresentationFormat,
  computePresentationPlanHash,
  computeSemanticHash,
  defaultFormatForDeliveryKind,
  FORMAT_META,
  formatToDeliveryKind,
  loadUseCaseMatrix,
  renderCard,
  replayEvidence,
  resolveWorkspaceContext,
  selectShowcasePlan,
  selectWalkthroughPlan,
  validateBySchemaId
} = core;

// ---------------------------------------------------------------------------
// Trees on disk
// ---------------------------------------------------------------------------

const file = (path, text) => ({ kind: "file", path, text });
const directory = (path) => ({ kind: "directory", path });
const mode = (path, octal) => ({ kind: "mode", path, mode: octal });

function buildEntries(workspace, entries) {
  for (const entry of entries) {
    const target = join(workspace, entry.path);
    if (entry.kind !== "mode") {
      mkdirSync(dirname(target), { recursive: true });
    }
    switch (entry.kind) {
      case "file":
        writeFileSync(target, entry.text);
        break;
      case "directory":
        mkdirSync(target, { recursive: true });
        break;
      case "mode":
        chmodSync(target, entry.mode);
        break;
      default:
        throw new Error(`unknown tree entry ${entry.kind}`);
    }
  }
}

function removeWorkspace(workspace, entries) {
  for (const entry of [...entries].reverse()) {
    if (entry.kind === "mode") {
      chmodSync(join(workspace, entry.path), 0o755);
    }
  }
  rmSync(workspace, { recursive: true, force: true });
}

function tokenized(value, workspace) {
  return JSON.parse(JSON.stringify(value).split(workspace).join("<workspace>"));
}

function thrown(error) {
  return { code: error.code ?? null, message: error.message };
}

// ---------------------------------------------------------------------------
// Use-case rows (JSON text is YAML, and keeps its key order)
// ---------------------------------------------------------------------------

const ZERO_HASH = `sha256:${"0".repeat(64)}`;
const STALE_HASH = `sha256:${"a".repeat(64)}`;

function row(id, extra = {}) {
  return {
    id,
    title: `Row ${id}`,
    lifecycle: "active",
    value_tier: "core",
    journey_role: "golden",
    usage_frequency: "common",
    actor: "user",
    intent: "Exercise the planner.",
    preconditions: [],
    trigger: "The planner runs.",
    scenarios: [{ id: "main", kind: "steps", steps: [`Open ${id}`] }],
    observable_outcomes: [`${id} is shown`],
    host_applicability: [{ host_surface: "codex.cli", supported: true }],
    verification_policy: { mode: "none" },
    approval_policy: { mode: "none" },
    ...extra
  };
}

function useCaseFile(featureId, rows) {
  return (
    [
      "schema_version: 1",
      "feature:",
      `  id: ${featureId}`,
      "  name: Fixture feature",
      "  summary: A fixture feature.",
      "use_cases:",
      ...rows.map((item) => `  - ${JSON.stringify(item)}`)
    ].join("\n") + "\n"
  );
}

const CONFIG = [
  "schema_version: 1",
  "workspace_id: corpus",
  "data_root: .",
  "use_cases_dir: use-cases",
  "evidence_dir: evidence",
  "demo_capsules_dir: demo-capsules",
  "showcase_runs_dir: showcase-runs",
  "component_id: corpus-component",
  ""
].join("\n");

const featureFile = (featureId, rows) => file(`use-cases/${featureId}.yml`, useCaseFile(featureId, rows));

const requirements = (...items) => ({
  mode: "requirements",
  requirements: items.map(([kind, verifiers]) => ({ evidence_kind: kind, required_verifiers: verifiers, minimum_count: 1 }))
});

// ---------------------------------------------------------------------------
// Evidence ledger lines
// ---------------------------------------------------------------------------

const lines = (...items) => items.map((item) => (typeof item === "string" ? item : JSON.stringify(item))).join("\n") + "\n";

function recorded(id, targets, extra = {}) {
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
      targets,
      kind: "manual_observation",
      captured_at: "2026-01-02T03:04:05.678Z",
      result: "pass",
      summary: `Observed ${id}.`,
      producer: { type: "agent" },
      method: { type: "reported" }
    },
    ...extra
  };
}

function voided(id) {
  return {
    schema_version: 1,
    event_type: "evidence_voided",
    event_id: `${id}-e2`,
    aggregate_id: id,
    sequence: 2,
    recorded_at: "2026-01-03T00:00:00.000Z",
    actor_type: "user",
    host_surface: "claude.cli",
    idempotency_key: `key-${id}-2`,
    target_event_id: `${id}-e1`,
    reason: "Voided for the corpus."
  };
}

const ledger = (id, ...events) => file(`evidence/by-id/${id.slice(0, 2)}/${id}.jsonl`, lines(...events));

// A target whose semantic hash is the row's current hash, looked up once the
// matrix has loaded.
const current = (useCaseId) => ({ use_case_id: useCaseId, hash: "current" });
const stale = (useCaseId) => ({ use_case_id: useCaseId, hash: "stale" });

function resolveTargets(targets, matrix) {
  return targets.map((target) => {
    if (target.hash === undefined) {
      return target;
    }
    const match = matrix.addressableUseCases.find((item) => item.value.id === target.use_case_id);
    return {
      use_case_id: target.use_case_id,
      use_case_semantic_hash: target.hash === "current" && match ? match.semanticHash : STALE_HASH
    };
  });
}

// ---------------------------------------------------------------------------
// Plan cases
// ---------------------------------------------------------------------------

const request = (extra = {}) => ({
  audience: "reviewer",
  timeboxSeconds: 3600,
  maxItems: 50,
  hostSurface: "codex.cli",
  generatedAt: "2026-06-25T12:00:00.000Z",
  ...extra
});

function loadedRow(entry, index) {
  // Members spelled `undefined` are dropped, as they are from the corpus JSON.
  const value = JSON.parse(JSON.stringify(entry.value));
  return {
    value,
    feature: { id: entry.feature_id, name: "Fixture feature", summary: "A fixture feature." },
    semanticHash: computeSemanticHash(value),
    source: { path: `use-cases/${entry.feature_id}.yml`, jsonPointer: `/use_cases/${index}`, fileByteHash: ZERO_HASH }
  };
}

// Validated as the wire JSON the CLI emits: AJV would otherwise see an
// in-memory `undefined` member (an unknown score rank) that the wire omits.
function schemaRecord(fileName, value) {
  const wire = JSON.parse(JSON.stringify(value));
  const result = validateBySchemaId(`https://use-cases.dev/schemas/v1/${fileName}`, wire);
  return { valid: result.ok, diagnostics: result.diagnostics };
}

function runPlan(testCase) {
  const workspace = realpathSync(mkdtempSync(join(tmpdir(), "use-cases-presentation-")));
  const tree = [...(testCase.tree ?? [])];
  const after = testCase.after ?? [];
  try {
    buildEntries(workspace, tree);
    const context = resolveWorkspaceContext({ workspaceRoot: workspace });
    const rows = testCase.rows?.map(loadedRow);
    const matrix = rows
      ? buildMatrixSnapshot({ context, files: [], candidates: rows, diagnostics: testCase.matrix_diagnostics ?? [] })
      : loadUseCaseMatrix({ context });
    const evidenceEntries = (testCase.ledgers ?? []).map(({ id, targets, voided: isVoided, text }) =>
      text !== undefined
        ? file(`evidence/by-id/${id.slice(0, 2)}/${id}.jsonl`, text)
        : isVoided
          ? ledger(id, recorded(id, resolveTargets(targets, matrix)), voided(id))
          : ledger(id, recorded(id, resolveTargets(targets, matrix)))
    );
    buildEntries(workspace, evidenceEntries);
    tree.push(...evidenceEntries);
    const evidence = replayEvidence({ context });
    buildEntries(workspace, after);

    const select = testCase.mode === "showcase" ? selectShowcasePlan : selectWalkthroughPlan;
    clockMilliseconds = testCase.clock_milliseconds ?? null;
    let result;
    let record;
    try {
      result = select({ context, matrix, evidence, request: testCase.request });
    } catch (error) {
      record = { throws: thrown(error) };
    } finally {
      clockMilliseconds = null;
    }
    if (!record) {
      record = {
        result,
        result_validation: schemaRecord("presentation-plan-result.schema.json", result),
        plan_validation: result.plan === null ? null : schemaRecord("presentation-plan.schema.json", result.plan),
        plan_hash_recomputed: result.plan === null ? null : computePresentationPlanHash(result.plan),
        cards: (result.plan?.selected_items ?? []).map((item) => ({ plan_item_id: item.plan_item_id, text: renderCard(item) }))
      };
    }
    return tokenized(
      {
        name: testCase.name,
        mode: testCase.mode,
        tree,
        ...(testCase.rows ? { rows: rows.map((item, index) => ({ feature_id: testCase.rows[index].feature_id, value: item.value, semantic_hash: item.semanticHash })) } : {}),
        ...(testCase.matrix_diagnostics ? { matrix_diagnostics: testCase.matrix_diagnostics } : {}),
        after,
        request: testCase.request,
        ...(testCase.clock_milliseconds !== undefined ? { clock_milliseconds: testCase.clock_milliseconds } : {}),
        ...record
      },
      workspace
    );
  } finally {
    removeWorkspace(workspace, [...tree, ...after]);
  }
}

// Ids whose ICU (`localeCompare`) order and UTF-16 code-unit order disagree:
// code units put `-` < `.` < `0` < `_` < `a`; ICU puts `_` < `-` < `.` < `0` < `a`.
const DISAGREEING = ["a-b", "a_b", "a.b", "a0", "ab"];

const basicRows = [
  featureFile("shop", [
    row("shop.checkout.golden", { value_tier: "critical", source_refs: [{ kind: "file", path: "src/checkout.ts" }] }),
    row("shop.checkout.alternate", { value_tier: "critical", journey_role: "alternate", usage_frequency: "occasional" }),
    row("shop.refund.edge", { value_tier: "core", journey_role: "edge", usage_frequency: "rare" }),
    row("shop.coupon.negative", { value_tier: "supporting", journey_role: "negative" }),
    row("shop.outage.failure", { value_tier: "core", journey_role: "failure", usage_frequency: "occasional" }),
    row("shop.theme.golden", {
      value_tier: "long_tail",
      usage_frequency: "rare",
      source_refs: [{ kind: "file", path: "src/theme.ts" }]
    })
  ])
];

const planCases = [
  // --- profiles, limits and the timebox -----------------------------------
  { name: "showcase_default_ranking", mode: "showcase", tree: basicRows, request: request() },
  { name: "walkthrough_default_ranking", mode: "walkthrough", tree: basicRows, request: request() },
  {
    name: "showcase_changed_path_beats_value",
    mode: "showcase",
    tree: basicRows,
    request: request({ changedPaths: ["./src/theme.ts", "src\\other.ts"] })
  },
  {
    name: "walkthrough_changed_path_beats_value",
    mode: "walkthrough",
    tree: basicRows,
    request: request({ changedPaths: ["src\\theme.ts"] })
  },
  { name: "max_items_zero", mode: "showcase", tree: basicRows, request: request({ maxItems: 0 }) },
  { name: "max_items_zero_walkthrough", mode: "walkthrough", tree: basicRows, request: request({ maxItems: 0 }) },
  { name: "max_items_one", mode: "showcase", tree: basicRows, request: request({ maxItems: 1 }) },
  { name: "max_items_exactly_fits", mode: "showcase", tree: basicRows, request: request({ maxItems: 6 }) },
  { name: "max_items_over", mode: "walkthrough", tree: basicRows, request: request({ maxItems: 7 }) },
  { name: "max_items_negative", mode: "showcase", tree: basicRows, request: request({ maxItems: -1 }) },
  { name: "max_items_fractional", mode: "showcase", tree: basicRows, request: request({ maxItems: 1.5 }) },
  { name: "max_items_omitted_uses_profile_default", mode: "showcase", tree: basicRows, request: request({ maxItems: undefined }) },
  { name: "max_items_omitted_walkthrough_default", mode: "walkthrough", tree: basicRows, request: request({ maxItems: undefined }) },
  { name: "timebox_excludes_as_max_items", mode: "showcase", tree: basicRows, request: request({ timeboxSeconds: 250 }) },
  { name: "timebox_exactly_fits", mode: "showcase", tree: basicRows, request: request({ timeboxSeconds: 240 }) },
  { name: "timebox_one_second_short", mode: "showcase", tree: basicRows, request: request({ timeboxSeconds: 239 }) },
  { name: "timebox_below_one_estimate", mode: "showcase", tree: basicRows, request: request({ timeboxSeconds: 119 }) },
  { name: "timebox_walkthrough", mode: "walkthrough", tree: basicRows, request: request({ timeboxSeconds: 540 }) },
  { name: "timebox_zero_uses_profile_default", mode: "showcase", tree: basicRows, request: request({ timeboxSeconds: 0, maxItems: 9 }) },
  { name: "timebox_zero_walkthrough_default", mode: "walkthrough", tree: basicRows, request: request({ timeboxSeconds: 0, maxItems: 9 }) },
  { name: "timebox_negative", mode: "showcase", tree: basicRows, request: request({ timeboxSeconds: -1 }) },
  { name: "timebox_fractional", mode: "showcase", tree: basicRows, request: request({ timeboxSeconds: 240.5 }) },

  // --- audience, host and request fields ----------------------------------
  { name: "audience_passes_through", mode: "showcase", tree: basicRows, request: request({ audience: "Equipe é 🚀" }) },
  { name: "audience_empty", mode: "showcase", tree: basicRows, request: request({ audience: "" }) },
  {
    name: "host_surface_omitted_is_unknown",
    mode: "showcase",
    tree: basicRows,
    request: request({ hostSurface: undefined })
  },
  {
    name: "freshness_evaluated_at_separate",
    mode: "showcase",
    tree: basicRows,
    request: request({ freshnessEvaluatedAt: "2026-06-24T00:00:00.000Z" })
  },
  {
    name: "generated_at_read_from_clock",
    mode: "walkthrough",
    tree: basicRows,
    clock_milliseconds: 1782388800123,
    request: request({ generatedAt: undefined })
  },
  {
    name: "generated_at_with_punctuation_and_unicode",
    mode: "showcase",
    tree: basicRows,
    request: request({ generatedAt: "__İstanbul K-Time.." })
  },
  { name: "generated_at_empty", mode: "showcase", tree: basicRows, request: request({ generatedAt: "" }) },
  {
    name: "changed_paths_sort_by_code_unit",
    mode: "showcase",
    tree: basicRows,
    request: request({
      changedPaths: ["src/b.ts", ...DISAGREEING.map((key) => `src/${key}.ts`), "src/B.ts", "./src/é.ts", "src\\é.ts", "src/b.ts", "././src/x.ts"]
    })
  },

  // --- eligibility ----------------------------------------------------------
  {
    name: "eligibility_exclusions",
    mode: "showcase",
    tree: [
      featureFile("elig", [
        row("elig.active"),
        { id: "elig.planned", title: "Planned", lifecycle: "planned", value_tier: "critical", journey_role: "golden", usage_frequency: "common" },
        { id: "elig.deprecated", title: "Deprecated", lifecycle: "deprecated", value_tier: "core", journey_role: "edge", usage_frequency: "rare" },
        { id: "elig.removed", title: "Removed", lifecycle: "removed", value_tier: "core", journey_role: "edge", usage_frequency: "rare" },
        row("elig.unsupported", { host_applicability: [{ host_surface: "codex.cli", supported: false }] }),
        row("elig.other_host", { host_applicability: [{ host_surface: "claude.cli", supported: true }] }),
        row("elig.many_hosts", {
          host_applicability: [
            { host_surface: "claude.cli", supported: true },
            { host_surface: "codex.cli", supported: true }
          ]
        })
      ])
    ],
    request: request()
  },
  {
    name: "eligibility_unknown_host_matches_everything",
    mode: "walkthrough",
    tree: [
      featureFile("elig", [
        row("elig.unsupported", { host_applicability: [{ host_surface: "codex.cli", supported: false }] }),
        row("elig.other_host", { host_applicability: [{ host_surface: "claude.cli", supported: true }] })
      ])
    ],
    request: request({ hostSurface: "unknown" })
  },
  {
    name: "requested_use_cases_only",
    mode: "showcase",
    tree: [
      ...basicRows,
      featureFile("extra", [
        { id: "extra.planned", title: "Planned", lifecycle: "planned", value_tier: "critical", journey_role: "golden", usage_frequency: "common" }
      ])
    ],
    request: request({ requestedUseCaseIds: ["shop.theme.golden", "extra.planned", "shop.refund.edge", "not.a.row"] })
  },
  {
    name: "requested_empty_list_requests_everything",
    mode: "showcase",
    tree: basicRows,
    request: request({ requestedUseCaseIds: [] })
  },
  {
    name: "no_eligible_items",
    mode: "showcase",
    tree: [
      featureFile("none", [
        { id: "none.planned", title: "Planned", lifecycle: "planned", value_tier: "critical", journey_role: "golden", usage_frequency: "common" },
        row("none.other_host", { host_applicability: [{ host_surface: "claude.cli", supported: true }] })
      ])
    ],
    request: request()
  },
  {
    name: "no_eligible_items_counts_requested_exclusions",
    mode: "walkthrough",
    tree: basicRows,
    request: request({ requestedUseCaseIds: ["missing.row"] })
  },
  { name: "empty_matrix", mode: "showcase", tree: [], request: request() },

  // --- ranking: each comparator level decides ------------------------------
  {
    name: "comparator_changed_level",
    mode: "showcase",
    tree: [
      featureFile("a", [row("a.important", { value_tier: "critical" })]),
      featureFile("b", [
        row("b.changed", {
          value_tier: "long_tail",
          journey_role: "failure",
          usage_frequency: "rare",
          source_refs: [{ kind: "file", path: "lib/changed.ts" }]
        })
      ])
    ],
    request: request({ changedPaths: ["lib/changed.ts"] })
  },
  {
    name: "comparator_value_level",
    mode: "showcase",
    tree: [
      featureFile("a", [row("a.core", { value_tier: "core", journey_role: "golden", usage_frequency: "common" })]),
      featureFile("b", [row("b.critical", { value_tier: "critical", journey_role: "failure", usage_frequency: "rare" })]),
      featureFile("c", [row("c.supporting", { value_tier: "supporting" }), row("c.long_tail", { value_tier: "long_tail" })])
    ],
    request: request()
  },
  {
    name: "comparator_journey_level_showcase",
    mode: "showcase",
    tree: [
      featureFile("a", [
        row("a.failure", { journey_role: "failure" }),
        row("a.negative", { journey_role: "negative" }),
        row("a.edge", { journey_role: "edge" }),
        row("a.alternate", { journey_role: "alternate" })
      ]),
      featureFile("b", [row("b.golden", { journey_role: "golden", usage_frequency: "rare" })])
    ],
    request: request()
  },
  {
    name: "comparator_journey_level_walkthrough_ties_coverage",
    mode: "walkthrough",
    tree: [
      featureFile("a", [
        row("a.failure", { journey_role: "failure" }),
        row("a.negative", { journey_role: "negative" }),
        row("a.edge", { journey_role: "edge" }),
        row("a.alternate", { journey_role: "alternate" }),
        row("a.edge2", { journey_role: "edge", usage_frequency: "rare" })
      ]),
      featureFile("b", [row("b.golden", { journey_role: "golden", usage_frequency: "rare", value_tier: "supporting" })])
    ],
    request: request()
  },
  {
    name: "comparator_frequency_level",
    mode: "showcase",
    tree: [
      featureFile("a", [row("a.rare", { usage_frequency: "rare" }), row("a.occasional", { usage_frequency: "occasional" })]),
      featureFile("b", [row("b.common", { usage_frequency: "common" })])
    ],
    request: request()
  },
  {
    name: "comparator_feature_level_locale_order",
    mode: "showcase",
    tree: DISAGREEING.map((key, index) => featureFile(`f.${key}`, [row(`z${index}.row`)])),
    request: request()
  },
  {
    name: "comparator_use_case_level_locale_order",
    mode: "showcase",
    tree: [featureFile("same", [...DISAGREEING].reverse().map((key) => row(`k.${key}`)))],
    request: request()
  },
  {
    name: "comparator_feature_level_walkthrough",
    mode: "walkthrough",
    tree: DISAGREEING.map((key, index) => featureFile(`f.${key}`, [row(`z${index}.row`, { journey_role: "edge" })])),
    request: request()
  },
  {
    name: "exclusions_keep_matrix_order",
    mode: "showcase",
    tree: [
      featureFile("a", [row("a.first", { value_tier: "long_tail" }), row("a.second", { value_tier: "supporting" })]),
      featureFile("b", [row("b.third", { value_tier: "critical" }), row("b.fourth", { value_tier: "core" })])
    ],
    request: request({ maxItems: 1 })
  },

  // --- walkthrough ordering and sections ----------------------------------
  {
    name: "walkthrough_role_slots",
    mode: "walkthrough",
    tree: [
      featureFile("a", [
        row("a.failure", { journey_role: "failure" }),
        row("a.negative", { journey_role: "negative" }),
        row("a.edge", { journey_role: "edge" }),
        row("a.alternate", { journey_role: "alternate" }),
        row("a.failure2", { journey_role: "failure", value_tier: "critical" }),
        row("a.golden_supporting", { journey_role: "golden", value_tier: "supporting" }),
        row("a.golden_core", { journey_role: "golden", value_tier: "core", usage_frequency: "rare" })
      ])
    ],
    request: request()
  },
  {
    name: "walkthrough_no_critical_or_core_golden",
    mode: "walkthrough",
    tree: [
      featureFile("a", [
        row("a.golden", { journey_role: "golden", value_tier: "supporting" }),
        row("a.edge", { journey_role: "edge", value_tier: "critical" })
      ])
    ],
    request: request()
  },
  {
    name: "walkthrough_critical_golden_wins_first_slot",
    mode: "walkthrough",
    tree: [
      featureFile("a", [
        row("a.core.golden", { journey_role: "golden", value_tier: "core" }),
        row("a.critical.golden", { journey_role: "golden", value_tier: "critical", usage_frequency: "rare" }),
        row("a.critical.edge", { journey_role: "edge", value_tier: "critical" })
      ])
    ],
    request: request()
  },
  {
    name: "walkthrough_sections_without_golden_ids",
    mode: "walkthrough",
    tree: [featureFile("a", [row("a.one", { journey_role: "edge" }), row("a.two", { journey_role: "negative" })])],
    request: request()
  },
  {
    name: "walkthrough_sections_match_dot_golden_only",
    mode: "walkthrough",
    tree: [
      featureFile("a", [row("a.nongolden"), row("a.golden", { journey_role: "edge" })]),
      featureFile("golden", [row("golden.first", { journey_role: "negative" })])
    ],
    request: request()
  },
  {
    name: "walkthrough_sections_all_golden_ids",
    mode: "walkthrough",
    tree: [featureFile("a", [row("a.one.golden"), row("a.two.golden_path", { journey_role: "edge" })])],
    request: request()
  },

  // --- integrity and strict mode -------------------------------------------
  {
    name: "partial_matrix_tolerated",
    mode: "showcase",
    tree: [
      ...basicRows,
      featureFile("broken", [row("broken.ref", { related_use_cases: ["nowhere.row"] })]),
      file("use-cases/damaged.yml", "schema_version: 1\nfeature: [\n")
    ],
    request: request()
  },
  {
    name: "partial_matrix_strict_blocks",
    mode: "showcase",
    tree: [...basicRows, file("use-cases/damaged.yml", "schema_version: 1\nfeature: [\n")],
    request: request({ strict: true })
  },
  {
    name: "partial_matrix_strict_blocks_before_no_eligible",
    mode: "walkthrough",
    tree: [
      featureFile("none", [
        { id: "none.planned", title: "Planned", lifecycle: "planned", value_tier: "critical", journey_role: "golden", usage_frequency: "common" }
      ]),
      file("use-cases/damaged.yml", "schema_version: 1\nfeature: [\n")
    ],
    request: request({ strict: true })
  },
  {
    name: "strict_with_clean_input_generates",
    mode: "showcase",
    tree: basicRows,
    request: request({ strict: true })
  },
  {
    name: "strict_false_with_partial_input_generates",
    mode: "walkthrough",
    tree: [...basicRows, file("use-cases/damaged.yml", "schema_version: 1\nfeature: [\n")],
    request: request({ strict: false })
  },
  {
    name: "unusable_matrix",
    mode: "showcase",
    tree: [file("use-cases/damaged.yml", "schema_version: 1\nfeature: [\n")],
    request: request()
  },
  {
    name: "torn_evidence_is_partial",
    mode: "showcase",
    tree: basicRows,
    ledgers: [
      { id: "ev-good", targets: [current("shop.checkout.golden")] },
      { id: "ev-torn", text: `${JSON.stringify(recorded("ev-torn", [{ use_case_id: "shop.theme.golden", use_case_semantic_hash: STALE_HASH }]))}\n{"torn` }
    ],
    request: request()
  },
  {
    name: "torn_evidence_strict_blocks",
    mode: "walkthrough",
    tree: basicRows,
    ledgers: [{ id: "ev-torn", text: `{"torn` }],
    request: request({ strict: true })
  },
  {
    name: "unknown_scope_damage_hides_evidence",
    mode: "showcase",
    tree: basicRows,
    ledgers: [
      { id: "ev-good", targets: [current("shop.checkout.golden")] },
      { id: "ev-foreign", text: `{"not":"an event"}\n` }
    ],
    request: request()
  },

  // --- evidence readiness and formats --------------------------------------
  {
    name: "evidence_readiness_and_formats",
    mode: "showcase",
    tree: [
      featureFile("ev", [
        row("ev.live.current", { verification_policy: requirements(["live_demo", ["agent"]]) }),
        row("ev.test.stale", { verification_policy: requirements(["test_result", ["ci"]], ["command_result", ["ci", "agent"]]) }),
        row("ev.test.missing", { verification_policy: requirements(["test_result", ["ci"]]) }),
        row("ev.none.current"),
        row("ev.user.verifier", { verification_policy: requirements(["manual_observation", ["user"]]) }),
        row("ev.approval.ask", { approval_policy: { mode: "ask", required_for_release: true } }),
        row("ev.voided", { verification_policy: requirements(["live_demo", ["agent"]]) }),
        row("ev.gherkin", {
          scenarios: [
            { id: "g1", kind: "gherkin", given: ["A given"], when: ["A when"], then: ["A then"] },
            { id: "s2", kind: "steps", steps: ["Step two"], observable_outcomes: ["Outcome two", "ev.gherkin is shown"] }
          ]
        })
      ])
    ],
    ledgers: [
      { id: "ev-live", targets: [current("ev.live.current"), current("ev.none.current")] },
      { id: "ev-live2", targets: [stale("ev.live.current")] },
      { id: "ev-stale", targets: [stale("ev.test.stale")] },
      { id: "ev-void", targets: [current("ev.voided")], voided: true }
    ],
    request: request({ maxItems: 20 })
  },
  {
    name: "evidence_readiness_and_formats_walkthrough",
    mode: "walkthrough",
    tree: [
      featureFile("ev", [
        row("ev.live.current", { verification_policy: requirements(["live_demo", ["agent"]]) }),
        row("ev.test.stale", { verification_policy: requirements(["test_result", ["ci"]], ["live_demo", ["user"]]) }),
        row("ev.test.missing", { verification_policy: requirements(["test_result", ["ci"]]) }),
        row("ev.approval.ask", { approval_policy: { mode: "ask" }, verification_policy: requirements(["test_result", ["ci"]]) })
      ])
    ],
    ledgers: [
      { id: "ev-live", targets: [current("ev.live.current")] },
      { id: "ev-stale", targets: [stale("ev.test.stale")] }
    ],
    request: request()
  },

  // --- the workflow snapshot reads use-cases.yml as text -------------------
  {
    name: "workflow_from_config",
    mode: "showcase",
    tree: [...basicRows, file("use-cases.yml", `${CONFIG}default_workflow_mode: backfill\n`)],
    request: request()
  },
  {
    name: "workflow_config_without_mode",
    mode: "showcase",
    tree: [...basicRows, file("use-cases.yml", CONFIG)],
    request: request()
  },
  {
    name: "workflow_value_crosses_newline",
    mode: "showcase",
    tree: basicRows,
    after: [file("use-cases.yml", "default_workflow_mode:\nother_key: x\n")],
    request: request()
  },
  {
    name: "workflow_quoted_value",
    mode: "showcase",
    tree: basicRows,
    after: [file("use-cases.yml", "default_workflow_mode: \"audit_only\"\n")],
    request: request()
  },
  {
    name: "workflow_first_capturing_line_wins",
    mode: "walkthrough",
    tree: basicRows,
    after: [file("use-cases.yml", "  default_workflow_mode: indented\ndefault_workflow_mode: 'x'\r\ndefault_workflow_mode:\t Custom_Mode9\ndefault_workflow_mode: later\n")],
    request: request()
  },
  {
    name: "workflow_line_separator_starts_a_line",
    mode: "walkthrough",
    tree: basicRows,
    after: [file("use-cases.yml", "x: 1 default_workflow_mode: migration\n")],
    request: request()
  },
  {
    name: "workflow_config_is_a_directory",
    mode: "showcase",
    tree: basicRows,
    after: [directory("use-cases.yml")],
    request: request()
  },
  {
    name: "workflow_config_unreadable",
    mode: "showcase",
    tree: basicRows,
    after: [file("use-cases.yml", "default_workflow_mode: backfill\n"), mode("use-cases.yml", 0o000)],
    request: request()
  },

  // --- rows handed straight to buildMatrixSnapshot -------------------------
  {
    name: "rows_not_runnable",
    mode: "showcase",
    rows: [
      { feature_id: "raw", value: row("raw.no_scenarios", { scenarios: undefined }) },
      { feature_id: "raw", value: row("raw.no_outcomes", { observable_outcomes: undefined }) },
      { feature_id: "raw", value: row("raw.blank_steps", { scenarios: [{ id: "s", kind: "steps", steps: ["", 7, null] }] }) },
      {
        feature_id: "raw",
        value: row("raw.steps_not_array", {
          scenarios: [{ id: "s", kind: "steps", steps: "not a list", given: ["Given text"], when: "skip", then: [3, "Then text"] }]
        })
      },
      { feature_id: "raw", value: row("raw.scenario_outcomes_only", { observable_outcomes: undefined, scenarios: [{ id: "s", steps: ["Go"], observable_outcomes: ["Seen"] }] }) },
      { feature_id: "raw", value: row("raw.empty_scenarios", { scenarios: [] }) }
    ],
    request: request()
  },
  {
    name: "rows_policy_shapes",
    mode: "showcase",
    rows: [
      { feature_id: "raw", value: row("raw.policy_missing", { verification_policy: undefined, approval_policy: undefined }) },
      { feature_id: "raw", value: row("raw.policy_string", { verification_policy: "requirements", approval_policy: ["ask"] }) },
      {
        feature_id: "raw",
        value: row("raw.requirements_filtered", {
          verification_policy: {
            mode: "requirements",
            extra: true,
            requirements: [
              { evidence_kind: "live_demo", required_verifiers: ["agent", 1], minimum_count: 1 },
              { evidence_kind: "test_result", required_verifiers: ["ci"] },
              "not a record",
              { minimum_count: 2.5, required_verifiers: [], evidence_kind: "command_result", note: "kept order" }
            ]
          }
        })
      },
      { feature_id: "raw", value: row("raw.requirements_not_array", { verification_policy: { mode: "requirements", requirements: {} } }) },
      { feature_id: "raw", value: row("raw.approval_null", { approval_policy: null }) }
    ],
    request: request()
  },
  {
    name: "rows_outcomes_are_unique_by_code_unit",
    mode: "walkthrough",
    rows: [
      {
        feature_id: "raw",
        value: row("raw.unicode", {
          scenarios: [
            { id: "s1", kind: "steps", steps: ["café", "café"], observable_outcomes: ["café", "café", "café"] }
          ],
          observable_outcomes: ["café", "plain"]
        })
      }
    ],
    request: request()
  },
  {
    name: "rows_unknown_score_values",
    mode: "showcase",
    rows: [
      { feature_id: "raw", value: row("raw.b_unknown_tier", { value_tier: "mythic" }) },
      { feature_id: "raw", value: row("raw.a_critical", { value_tier: "critical" }) },
      { feature_id: "raw", value: row("raw.c_unknown_role", { journey_role: "detour" }) }
    ],
    request: request()
  },
  {
    name: "rows_matrix_diagnostic_makes_input_partial",
    mode: "walkthrough",
    rows: [{ feature_id: "raw", value: row("raw.only") }],
    matrix_diagnostics: [{ code: "corpus_error", severity: "error", message: "Corpus-injected error." }],
    request: request()
  },
  {
    name: "rows_warning_diagnostic_keeps_input_complete",
    mode: "walkthrough",
    rows: [{ feature_id: "raw", value: row("raw.only") }],
    matrix_diagnostics: [{ code: "corpus_warning", severity: "warning", message: "Corpus-injected warning." }],
    request: request()
  },
  {
    name: "rows_host_applicability_empty_matches",
    mode: "showcase",
    rows: [
      { feature_id: "raw", value: row("raw.hosts_empty", { host_applicability: [] }) },
      { feature_id: "raw", value: row("raw.hosts_missing", { host_applicability: undefined }) }
    ],
    request: request()
  },
  {
    name: "rows_changed_path_normalization",
    mode: "showcase",
    rows: [
      { feature_id: "raw", value: row("raw.backslash", { value_tier: "long_tail", source_refs: [{ kind: "file", path: "src\\win.ts" }] }) },
      { feature_id: "raw", value: row("raw.dotslash", { value_tier: "long_tail", source_refs: [{ kind: "file", path: "./src/dot.ts" }] }) },
      { feature_id: "raw", value: row("raw.not_file", { value_tier: "long_tail", source_refs: [{ kind: "symbol", path: "src/sym.ts" }] }) },
      { feature_id: "raw", value: row("raw.decomposed", { value_tier: "long_tail", source_refs: [{ kind: "file", path: "src/café.ts" }] }) },
      { feature_id: "raw", value: row("raw.plain", { value_tier: "critical" }) }
    ],
    request: request({ changedPaths: ["src/win.ts", ".\\src\\dot.ts", "src/sym.ts", "src/café.ts"] })
  },
  {
    name: "rows_requested_ids_are_code_units",
    mode: "showcase",
    rows: [
      { feature_id: "raw", value: row("raw.k") },
      { feature_id: "raw", value: row("raw.other") }
    ],
    request: request({ requestedUseCaseIds: ["raw.K", "raw.other"] })
  },
  {
    name: "rows_evidence_targets_compare_exactly",
    mode: "showcase",
    rows: [{ feature_id: "raw", value: row("raw.target") }],
    ledgers: [
      { id: "ev-exact", targets: [{ use_case_id: "raw.target", use_case_semantic_hash: "sha256:not-the-hash" }] },
      { id: "ev-other", targets: [{ use_case_id: "raw.targets", use_case_semantic_hash: STALE_HASH }] }
    ],
    request: request()
  }
];

// Fixture workspaces the TypeScript's own tests plan against.
function fixtureTree(name) {
  const root = join(repositoryRoot, "tests/fixtures/workspaces", name);
  return walkFiles(root).map((full) => file(relative(root, full), readFileSync(full, "utf8")));
}

function walkFiles(root, current = root) {
  const out = [];
  for (const name of readdirSync(current).sort()) {
    const full = join(current, name);
    if (lstatSync(full).isDirectory()) {
      out.push(...walkFiles(root, full));
    } else {
      out.push(full);
    }
  }
  return out;
}

for (const fixture of ["presentation-selection", "presentation-partial", "presentation-no-eligible"]) {
  for (const selectionMode of ["showcase", "walkthrough"]) {
    planCases.push({
      name: `fixture_${fixture.replaceAll("-", "_")}_${selectionMode}`,
      mode: selectionMode,
      tree: fixtureTree(fixture),
      request: request({ changedPaths: ["src/checkout/flow.ts"], maxItems: undefined, timeboxSeconds: 0 })
    });
    planCases.push({
      name: `fixture_${fixture.replaceAll("-", "_")}_${selectionMode}_strict`,
      mode: selectionMode,
      tree: fixtureTree(fixture),
      request: request({ strict: true, hostSurface: "claude.cli" })
    });
  }
}

// This repository's own matrix, evidence and config, snapshotted.
const repositoryTree = [
  file("use-cases.yml", readFileSync(join(repositoryRoot, "use-cases.yml"), "utf8")),
  ...walkFiles(join(repositoryRoot, "use-cases"))
    .filter((full) => /\.ya?ml$/.test(full))
    .map((full) => file(relative(repositoryRoot, full), readFileSync(full, "utf8"))),
  ...walkFiles(join(repositoryRoot, "evidence")).map((full) => file(relative(repositoryRoot, full), readFileSync(full, "utf8")))
];
for (const selectionMode of ["showcase", "walkthrough"]) {
  for (const host of ["unknown", "claude.cli", "codex.cli"]) {
    planCases.push({
      name: `repository_${selectionMode}_${host.replaceAll(".", "_")}`,
      mode: selectionMode,
      tree: repositoryTree,
      request: request({ hostSurface: host, maxItems: undefined, timeboxSeconds: selectionMode === "showcase" ? 600 : 1800 })
    });
  }
}
planCases.push({
  name: "repository_walkthrough_everything",
  mode: "walkthrough",
  tree: repositoryTree,
  request: request({ hostSurface: "unknown", maxItems: 1000, timeboxSeconds: 1000000, changedPaths: ["packages/core/src/presentation/selectPlan.ts"] })
});

// ---------------------------------------------------------------------------
// Card cases
// ---------------------------------------------------------------------------

function makeItem(overrides = {}) {
  return {
    plan_item_id: "item.cards.row",
    presentation_format: "testing",
    delivery_kind: "live_demo",
    scenario_scope: "whole_use_case",
    use_case_id: "cards.row",
    use_case_title: "Show the welcome banner",
    scenario_ids: [],
    use_case_content_hash: ZERO_HASH,
    estimated_seconds: 120,
    estimate_source: "default_profile",
    setup_steps: [],
    resolved_steps: ["Open the app", "Sign in"],
    expected_observations: ["Banner shown", "Name greeted"],
    teardown_steps: [],
    required_permissions: [],
    safety_constraints: [],
    verification_policy_snapshot: { mode: "none" },
    approval_policy_snapshot: { mode: "none" },
    approval_resolution_required_at_run_start: false,
    required_evidence: [],
    evidence_summary: { readiness: "available_current", active_evidence_ids: ["ev.1", "ev.2"], basis: "active_evidence_semantic_hash_match" },
    freshness_summary: { state: "current", basis: "policy_match" },
    known_gaps: [],
    selection_reasons: [],
    selection_reason_codes: [],
    score_components: {},
    ...overrides
  };
}

const FORMATS = ["testing", "comparing", "inspecting", "reviewing", "user_led", "explaining"];
const noSteps = { resolved_steps: [], expected_observations: [] };

const cardCases = [];
for (const format of FORMATS) {
  cardCases.push({ name: `${format}_open`, item: makeItem({ presentation_format: format }) });
  cardCases.push({ name: `${format}_empty_slots`, item: makeItem({ presentation_format: format, ...noSteps }) });
  cardCases.push({ name: `${format}_one_step`, item: makeItem({ presentation_format: format, resolved_steps: ["Only step"], expected_observations: [] }) });
  cardCases.push({ name: `${format}_untitled`, item: makeItem({ presentation_format: format, use_case_title: undefined }) });
  cardCases.push({ name: `${format}_pass_recorded`, item: makeItem({ presentation_format: format }), result: { status: "pass", got: "Banner shown", evidenceId: "ev.2" } });
  cardCases.push({ name: `${format}_pass_unrecorded`, item: makeItem({ presentation_format: format }), result: { status: "pass", got: "Banner shown", evidenceId: "fabricated" } });
  cardCases.push({ name: `${format}_pass_without_evidence_id`, item: makeItem({ presentation_format: format }), result: { status: "pass", got: "Banner shown" } });
  cardCases.push({ name: `${format}_pass_empty_evidence_id`, item: makeItem({ presentation_format: format, evidence_summary: { readiness: "missing", active_evidence_ids: [""], basis: "b" } }), result: { status: "pass", evidenceId: "" } });
  cardCases.push({ name: `${format}_fail`, item: makeItem({ presentation_format: format }), result: { status: "fail", got: "Banner missing" } });
  cardCases.push({ name: `${format}_fail_without_got`, item: makeItem({ presentation_format: format }), result: { status: "fail" } });
  cardCases.push({ name: `${format}_got_without_status`, item: makeItem({ presentation_format: format }), result: { got: "Seen anyway" } });
  cardCases.push({ name: `${format}_empty_result`, item: makeItem({ presentation_format: format }), result: {} });
  cardCases.push({ name: `${format}_answered_by_human`, item: makeItem({ presentation_format: format }), result: { answeredByHuman: true } });
  cardCases.push({ name: `${format}_answered_by_agent`, item: makeItem({ presentation_format: format }), result: { answeredByHuman: false } });
  cardCases.push({ name: `${format}_answered_with_pass`, item: makeItem({ presentation_format: format }), result: { answeredByHuman: true, status: "pass", got: "Yes" } });
  cardCases.push({ name: `${format}_status_without_answer`, item: makeItem({ presentation_format: format }), result: { status: "fail", got: "No" } });
}
cardCases.push(
  { name: "title_whitespace_only_falls_back_to_id", item: makeItem({ use_case_title: " \t\n " }) },
  { name: "title_trimmed_javascript_whitespace", item: makeItem({ use_case_title: "﻿  Padded title 　" }) },
  { name: "title_keeps_next_line_character", item: makeItem({ use_case_title: "Kept" }) },
  { name: "title_empty_falls_back_to_id", item: makeItem({ use_case_title: "" }) },
  { name: "text_with_unicode_and_markdown", item: makeItem({ presentation_format: "explaining", expected_observations: ["**bold** — café 🚀", "`code`"] }) },
  { name: "explaining_falls_back_to_steps", item: makeItem({ presentation_format: "explaining", expected_observations: [] }) },
  { name: "reviewing_empty_basis", item: makeItem({ presentation_format: "reviewing", evidence_summary: { readiness: "missing", active_evidence_ids: [], basis: "" } }) },
  { name: "testing_many_steps", item: makeItem({ resolved_steps: Array.from({ length: 11 }, (_, index) => `Step ${index}`) }) },
  { name: "comparing_three_steps_with_got", item: makeItem({ presentation_format: "comparing", resolved_steps: ["Bad", "Good", "Ignored"] }), result: { status: "fail", got: "Both allowed" } },
  { name: "comparing_empty_got_has_no_suffix", item: makeItem({ presentation_format: "comparing" }), result: { status: "fail", got: "" } },
  { name: "testing_fail_got_with_spaces_is_trimmed", item: makeItem(), result: { status: "fail", got: "  spaced  " } }
);

function runCard(testCase) {
  const record = { name: testCase.name, item: testCase.item, ...(testCase.result ? { result: testCase.result } : {}) };
  try {
    return { ...record, text: renderCard(testCase.item, testCase.result) };
  } catch (error) {
    return { ...record, throws: thrown(error) };
  }
}

// ---------------------------------------------------------------------------
// Helper probes
// ---------------------------------------------------------------------------

const generatedAtProbes = [
  "2026-06-25T12:00:00.000Z",
  "",
  "___",
  "...",
  "--a--",
  "İ",
  "K",
  "ß",
  "ΣΣ",
  "ABC-def_GHI",
  "🚀x🚀",
  "a b"
];

function helperProbes() {
  const loaded = loadedRow({ feature_id: "helpers", value: row("helpers.row") }, 0);
  const candidate = { useCase: loaded, eligible: true, changed: false, scoreComponents: {}, reasonCodes: [], reasons: [] };
  const planForHash = {
    schema_version: 1,
    plan_id: "plan.showcase.one",
    plan_content_hash: ZERO_HASH,
    generated_at: "2026-06-25T12:00:00.000Z",
    mode: "showcase",
    b: [1, { z: 1, a: 2 }],
    a: "text"
  };
  const hashCases = [
    { name: "volatile_members_removed", plan: planForHash },
    { name: "volatile_members_changed", plan: { ...planForHash, plan_id: "plan.other", generated_at: "later", plan_content_hash: "x" } },
    { name: "member_order_does_not_matter", plan: { a: "text", mode: "showcase", b: [1, { a: 2, z: 1 }], schema_version: 1 } },
    { name: "array_order_matters", plan: { ...planForHash, b: [{ z: 1, a: 2 }, 1] } },
    { name: "empty_plan", plan: {} }
  ].map((item) => ({ ...item, hash: computePresentationPlanHash(item.plan) }));

  // `compareCandidates` on its own, over candidates in an order no matrix
  // snapshot would hand it: the planner's inputs are already sorted by id.
  const probeCandidate = (featureId, id, scores) => ({
    useCase: loadedRow({ feature_id: featureId, value: row(id) }, 0),
    eligible: true,
    changed: false,
    scoreComponents: scores,
    reasonCodes: [],
    reasons: []
  });
  const tie = { changed: 0, value: 300, journey: 50, frequency: 30 };
  const comparatorSorts = [
    {
      name: "use_case_id_breaks_the_last_tie",
      candidates: ["ab", "a0", "a.b", "a_b", "a-b"].map((key) => probeCandidate("same", `k.${key}`, tie))
    },
    {
      name: "feature_id_before_use_case_id",
      candidates: [
        probeCandidate("f.b", "k.a", tie),
        probeCandidate("f_a", "k.c", tie),
        probeCandidate("f-a", "k.b", tie),
        probeCandidate("f.a", "k.d", tie)
      ]
    },
    {
      name: "scores_before_ids",
      candidates: [
        probeCandidate("a", "k.a", { changed: 0, value: 100, journey: 50, frequency: 30 }),
        probeCandidate("a", "k.b", { changed: 0, value: 100, journey: 50, frequency: 10 }),
        probeCandidate("z", "k.z", { changed: 1000, value: 100, journey: 10, frequency: 10 }),
        probeCandidate("a", "k.c", { changed: 0, value: 400, journey: 10, frequency: 10 }),
        probeCandidate("a", "k.d", { changed: 0, value: 100, journey: 40, frequency: 30 })
      ]
    }
  ].map((probe) => ({
    name: probe.name,
    candidates: probe.candidates.map((candidate) => ({
      feature_id: candidate.useCase.feature.id,
      use_case_id: candidate.useCase.value.id,
      score_components: candidate.scoreComponents
    })),
    sorted_ids: probe.candidates.slice().sort(core.compareCandidates).map((candidate) => candidate.useCase.value.id)
  }));

  const orderKeys = [...DISAGREEING, "A", "B", "a", "b", "_", "-", ".", "0"];
  return {
    plan_ids: ["showcase", "walkthrough"].flatMap((selectionMode) =>
      generatedAtProbes.map((generatedAt) => ({ mode: selectionMode, generated_at: generatedAt, plan_id: snapshotModule.planId(selectionMode, generatedAt) }))
    ),
    normalized_paths: [
      [],
      ["b", "a"],
      ["./a", "a", ".\\a", "a\\b\\c", "././x", "/abs", "a/./b"],
      [...DISAGREEING, "B", "é", "é", "🚀", "Ａ"]
    ].map((input) => ({ input, output: helpersModule.normalizePaths(input) })),
    exclusions: ["timebox", "max_items", "other"].map((reasonCode) => ({
      reason_code: reasonCode,
      exclusion: candidatesModule.exclusionFor(candidate, reasonCode)
    })),
    plan_hashes: hashCases,
    comparator_sorts: comparatorSorts,
    orders: {
      keys: orderKeys,
      locale: [...orderKeys].sort((left, right) => left.localeCompare(right)),
      code_unit: [...orderKeys].sort()
    },
    formats: {
      metadata: FORMATS.map((format) => ({ format, ...FORMAT_META[format] })),
      delivery_kinds: FORMATS.flatMap((format) =>
        ["live_demo", "evidence_review", "explanation"].map((base) => ({ format, base, delivery_kind: formatToDeliveryKind(format, base) }))
      ),
      defaults: ["live_demo", "evidence_review", "explanation"].map((kind) => ({ kind, format: defaultFormatForDeliveryKind(kind) })),
      choices: ["live_demo", "evidence_review", "explanation"].flatMap((base) =>
        [false, true].flatMap((needsUser) =>
          [false, true].map((isContrast) => ({ base, needs_user: needsUser, is_contrast: isContrast, format: choosePresentationFormat({ baseDeliveryKind: base, needsUser, isContrast }) }))
        )
      )
    },
    profile_digests: {
      showcase: computeSemanticHash(core.SHOWCASE_PROFILE),
      walkthrough: computeSemanticHash(core.WALKTHROUGH_PROFILE)
    }
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
  plans: planCases.map(runPlan),
  cards: cardCases.map(runCard),
  helpers: helperProbes()
};

const names = golden.plans.map((item) => item.name);
if (new Set(names).size !== names.length) {
  throw new Error("duplicate plan case name");
}

const json = asciiJson(golden);
let pounds = "#";
while (json.includes(`\\${pounds}`) || json.includes(`"""${pounds}`) || json.includes(`"${pounds}`)) {
  pounds += "#";
}
const contents = `// swiftlint:disable line_length single_line_closure_body
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript presentation planner. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/presentation returned,
// rendered or threw for the tree, rows, request or item beside it.
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-presentation-corpus.mjs
enum PresentationGoldenCorpus {
${nameList("planCaseNames", names)}${nameList("cardCaseNames", golden.cards.map((item) => item.name))}  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable line_length single_line_closure_body
`;
mkdirSync(testsDirectory, { recursive: true });
const targetPath = join(testsDirectory, "PresentationGoldenCorpus.swift");
writeFileSync(targetPath, contents);
if (!/^[\x00-\x7f]*$/.test(readFileSync(targetPath, "utf8"))) {
  throw new Error("PresentationGoldenCorpus.swift is not ASCII");
}
const sha = createHash("sha256").update(contents).digest("hex").slice(0, 12);
console.log(
  `wrote ${targetPath} (${sha}): ${golden.plans.length} plan cases ` +
    `(${golden.plans.filter((item) => item.throws).length} throw), ${golden.cards.length} card cases ` +
    `(${golden.cards.filter((item) => item.throws).length} throw)`
);
