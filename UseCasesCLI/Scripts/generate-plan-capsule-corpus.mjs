// Regenerates the CLI plan- and capsule-command corpus by running every case
// below through the REAL TypeScript CLI and recording exactly the bytes, exit
// codes and files it produced.
//
//   pnpm build
//   node UseCasesCLI/Scripts/generate-plan-capsule-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCLITests/Entry/PlanCapsuleGoldenCorpus.swift
//     For each case: how its sandbox was set up (files), then its STEPS in
//     order — CLI runs, file writes and mode changes. Every CLI run records its
//     argv, stdout, stderr and exit status; after the last step every file and
//     directory the sandbox holds is recorded (file modes and contents
//     included). Covers row 4e: `plan showcase`, `plan walkthrough`,
//     `plan cards`, and `capsule list|validate|plan|run`, golden, bad and edge,
//     in the JSON and human renderings.
//
// A sandbox is a temporary directory holding `demo-repo` (the workspace),
// `outside` and `home` (HOME for every run). Paths are recorded as
// placeholders: `$ROOT` for the temporary directory, `$SANDBOX` for
// `$ROOT/demo-repo`, `$CWD` for the directory the CLI ran in and `$REPO` for
// this repository.
//
// Every run gets exactly PATH and HOME — nothing else from this shell.
//
// PLAN FILES are baked into a case's setup as literals, because a generated
// plan does not depend on where its workspace is: the same matrix planned in
// two different sandboxes gives byte-identical plans (measured). A pre-pass
// runs `plan showcase`/`plan walkthrough` once, and the hand-edited variants
// are that plan with a member removed and `plan_content_hash` recomputed
// through the TypeScript's own `computePresentationPlanHash`, so each one is a
// plan `plan cards` accepts and only the edited member differs.
//
// Normalised by the Swift test on BOTH sides, never here: the millisecond ISO
// timestamps a capsule run stamps when no `--recorded-at` pins them, and the
// showcase run and event ids derived from the clock. Every plan is pinned with
// `--generated-at`, so no plan id, hash or `generated_at` is masked.
//
// Masked by the Swift test too: the message of a `parse_error` diagnostic and
// of `showcase_plan_file_unreadable`, which is V8's own `JSON.parse` wording
// (the row 3, 4b and 4d precedent in docs/rewrite/ladder-notes.md). Their
// codes, their `source_path` and everything around them are compared.
//
// Everything else — plan ids and content hashes, card text, semantic hashes,
// capsule verdicts, command output digests, idempotency keys — is compared byte
// for byte.
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
  ["cli", "commands/plan"],
  ["cli", "commands/capsule"],
  ["cli", "render"],
  ["cli", "runtime"],
  ["cli", "command/dispatch"],
  ["core", "presentation/selectPlan"],
  ["core", "presentation/renderCard"],
  ["core", "capsules/loadCapsule"],
  ["core", "capsules/runCapsule"]
];
for (const [pkg, name] of PORTED) {
  const source = statSync(join(repositoryRoot, `packages/${pkg}/src/${name}.ts`)).mtimeMs;
  const built = statSync(join(repositoryRoot, `packages/${pkg}/dist/${name}.js`)).mtimeMs;
  if (built < source) {
    throw new Error(`packages/${pkg}/dist/${name}.js is older than its source; run pnpm build first`);
  }
}

const { computePresentationPlanHash } = await import(join(repositoryRoot, "packages/core/dist/index.js"));

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

// A row with no verification policy plans as `explaining`; one whose
// requirements name `live_demo` plans as `testing`; any other requirement
// plans as `reviewing`; a `user` verifier plans as `user_led`. All four formats
// matter, because `plan cards` renders a different body for each and only
// `reviewing` reads `evidence_summary.basis`.
const POLICIES = {
  explain: `    verification_policy:
      mode: none
`,
  review: `    verification_policy:
      mode: requirements
      verifiers:
        script:
          kind: script
          evidence_kind: test_result
          command: ["true"]
      requirements:
        - evidence_kind: test_result
          required_verifiers: [script]
          minimum_count: 1
`,
  live: `    verification_policy:
      mode: requirements
      verifiers:
        script:
          kind: script
          evidence_kind: live_demo
          command: ["true"]
      requirements:
        - evidence_kind: live_demo
          required_verifiers: [script]
          minimum_count: 1
`,
  user: `    verification_policy:
      mode: requirements
      verifiers:
        script:
          kind: script
          evidence_kind: test_result
          command: ["true"]
      requirements:
        - evidence_kind: test_result
          required_verifiers: [user]
          minimum_count: 1
`
};

function row(id, policy, extra = "") {
  return `  - id: ${id}
    title: Row ${id}
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
${extra}    actor: agent
    intent: Exist so a plan can select it.
    preconditions: [Nothing.]
    trigger: An agent plans it.
    scenarios:
      - id: ${id}.golden_runs
        kind: steps
        steps: [Open the thing., Look at it.]
        observable_outcomes: [It reads as expected.]
    observable_outcomes: [A plan can select it.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
${POLICIES[policy]}    approval_policy:
      mode: none
`;
}

const shard = (featureId, rows) =>
  `schema_version: 1\nfeature:\n  id: ${featureId}\n  name: Probe\n  summary: Probe.\nuse_cases:\n${rows.join("")}`;

const MATRIX = shard("probe.core", [
  row("probe.core.explain", "explain"),
  row("probe.core.review", "review"),
  row("probe.core.live", "live"),
  row("probe.core.user", "user")
]);

const CHANGED = shard("probe.changed", [
  row("probe.changed.tagged", "explain", "    source_refs:\n      - kind: file\n        path: src/changed.ts\n")
]);

const CAPSULE_TOUR = `schema_version: 1
capsule_id: capsule.probe.tour
title: Probe tour
mode: showcase
description: Walk the probe rows with no commands.
audience: reviewer
timebox_seconds: 300
items:
  - use_case_id: probe.core.explain
    runbook:
      - kind: instruction
        text: Read the row out loud.
      - kind: observation
        text: It reads as expected.
permissions:
  command_execution: false
`;

const CAPSULE_COMMANDS = `schema_version: 1
capsule_id: capsule.probe.commands
title: Probe commands
mode: showcase
description: Run a command for the probe row.
audience: reviewer
timebox_seconds: 300
items:
  - use_case_id: probe.core.live
    runbook:
      - kind: instruction
        text: Run the probe command.
      - kind: command
        executable: /bin/echo
        argv: [probe-ran]
        working_directory: .
        expected_exit_codes: [0]
permissions:
  command_execution: true
`;

const capsuleWithCommand = (id, executable, argv, extra = {}) => `schema_version: 1
capsule_id: ${id}
title: Probe ${id}
mode: showcase
description: Probe.
audience: reviewer
timebox_seconds: 300
items:
  - use_case_id: probe.core.live
    runbook:
      - kind: command
        executable: ${executable}
        argv: [${argv.map((value) => JSON.stringify(value)).join(", ")}]
        working_directory: ${extra.workingDirectory ?? "."}
        expected_exit_codes: [${extra.expectedExitCodes ?? "0"}]
permissions:
  command_execution: ${extra.permitted ?? true}
`;

const CAPSULE_WALKTHROUGH = `schema_version: 1
capsule_id: capsule.probe.walkthrough
title: Probe walkthrough
mode: walkthrough
description: Narrate the probe rows.
audience: stakeholder
timebox_seconds: 1800
items:
  - use_case_id: probe.core.explain
    runbook:
      - kind: instruction
        text: Explain the row.
  - use_case_id: probe.core.review
    scenario_ids: [probe.core.review.golden_runs]
    runbook:
      - kind: instruction
        text: Show the earlier run.
permissions:
  command_execution: false
`;

const CAPSULE_BROKEN = "schema_version: 1\ncapsule_id: capsule.probe.broken\nmode: showcase\n";
const CAPSULE_UNKNOWN_ROW = `schema_version: 1
capsule_id: capsule.probe.unknown_row
title: Probe unknown row
mode: showcase
description: Names a row the matrix does not hold.
audience: reviewer
timebox_seconds: 300
items:
  - use_case_id: probe.core.nowhere
    runbook:
      - kind: instruction
        text: Cannot be planned.
permissions:
  command_execution: false
`;

const S = "$SANDBOX";
const R = "$ROOT";

function workspace(extra = {}) {
  return {
    files: {
      "demo-repo/use-cases.yml": CONFIG,
      "demo-repo/use-cases/probe.yml": MATRIX,
      ...extra
    }
  };
}

const capsules = (extra = {}) =>
  workspace({
    "demo-repo/demo-capsules/tour.yml": CAPSULE_TOUR,
    "demo-repo/demo-capsules/walkthrough.yml": CAPSULE_WALKTHROUGH,
    ...extra
  });

const empty = { files: {} };
const unconfigured = { files: { "demo-repo/use-cases/probe.yml": MATRIX } };
const brokenMatrix = workspace({ "demo-repo/use-cases/broken.yml": "schema_version: 1\nfeature:\n  id: probe.broken\n" });
const noRows = { files: { "demo-repo/use-cases.yml": CONFIG } };

// Steps.
const uc = (args) => ({ kind: "uc", args });
const write = (path, content) => ({ kind: "write", path, content });
const chmod = (path, mode) => ({ kind: "chmod", path, mode });

const repo = ["--repo", S];
const AT = ["--generated-at", "2026-06-25T12:00:00.000Z"];
const plan = (mode, ...rest) => uc(["plan", mode, ...repo, ...AT, ...rest]);
const cards = (...rest) => uc(["plan", "cards", ...repo, ...rest]);
const capsule = (verb, ...rest) => uc(["capsule", verb, ...repo, ...rest]);

// ---------------------------------------------------------------------------
// Plan files, computed once from the real planner

function scratchPlan(mode, files) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "uc-plan-seed-")));
  try {
    for (const [path, content] of Object.entries(files)) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), content);
    }
    const sandbox = join(root, "demo-repo");
    const result = spawnSync(
      process.execPath,
      [cliEntry, "plan", mode, "--repo", sandbox, ...AT, "--json"],
      { cwd: root, encoding: "utf8", env: { PATH: process.env.PATH, HOME: root } }
    );
    if (result.status !== 0) {
      throw new Error(`seed plan ${mode} failed (${result.status}): ${result.stdout}${result.stderr}`);
    }
    const parsed = JSON.parse(result.stdout);
    if (!parsed.data?.plan) {
      throw new Error(`seed plan ${mode} produced no plan`);
    }
    return parsed.data.plan;
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const serialize = (value) => `${JSON.stringify(value, null, 2)}\n`;
const clone = (value) => JSON.parse(JSON.stringify(value));

// Re-hash an edited plan so `loadPresentationPlanFile` accepts it: the edit
// under test must be the ONLY difference the command sees.
function rehashed(plan) {
  const edited = clone(plan);
  edited.plan_content_hash = computePresentationPlanHash(edited);
  return edited;
}

const SHOWCASE_PLAN = scratchPlan("showcase", workspace().files);
const WALKTHROUGH_PLAN = scratchPlan("walkthrough", workspace().files);

function editedPlan(edit) {
  const edited = clone(SHOWCASE_PLAN);
  edit(edited);
  return serialize(rehashed(edited));
}

const withoutFormats = editedPlan((plan) => {
  for (const item of plan.selected_items) {
    delete item.presentation_format;
  }
});
const withoutBasis = editedPlan((plan) => {
  for (const item of plan.selected_items) {
    delete item.evidence_summary.basis;
  }
});
const withoutEvidenceSummary = editedPlan((plan) => {
  for (const item of plan.selected_items) {
    delete item.evidence_summary;
  }
});
const unknownFormat = editedPlan((plan) => {
  plan.selected_items[0].presentation_format = "interpretive_dance";
});
const unknownDeliveryKind = editedPlan((plan) => {
  delete plan.selected_items[0].presentation_format;
  plan.selected_items[0].delivery_kind = "seance";
});
const withoutResolvedSteps = editedPlan((plan) => {
  for (const item of plan.selected_items) {
    delete item.resolved_steps;
  }
});
const noItems = editedPlan((plan) => {
  plan.selected_items = [];
  plan.sections = [];
});
const emptyStepsAndObservations = editedPlan((plan) => {
  for (const item of plan.selected_items) {
    item.resolved_steps = [];
    item.expected_observations = [];
  }
});
const blankTitle = editedPlan((plan) => {
  plan.selected_items[0].use_case_title = "   ";
});

const placeholderHash = serialize({
  ...clone(SHOWCASE_PLAN),
  plan_content_hash: `sha256:${"0".repeat(64)}`
});
const mismatchedHash = serialize({
  ...clone(SHOWCASE_PLAN),
  plan_content_hash: `sha256:${"a".repeat(64)}`
});

const planFiles = {
  "demo-repo/plans/showcase.json": serialize(SHOWCASE_PLAN),
  "demo-repo/plans/walkthrough.json": serialize(WALKTHROUGH_PLAN)
};

const withPlans = (extra = {}) => workspace({ ...planFiles, ...extra });

// ---------------------------------------------------------------------------
// Cases

const planCases = [
  ["plan_showcase_json", workspace(), [plan("showcase", "--json")]],
  ["plan_showcase_text", workspace(), [plan("showcase")]],
  ["plan_walkthrough_json", workspace(), [plan("walkthrough", "--json")]],
  ["plan_walkthrough_text", workspace(), [plan("walkthrough")]],
  ["plan_showcase_audience", workspace(), [plan("showcase", "--audience", "stakeholder", "--json")]],
  ["plan_showcase_empty_audience", workspace(), [plan("showcase", "--audience", "", "--json")]],
  ["plan_showcase_timebox", workspace(), [plan("showcase", "--timebox", "60", "--json")]],
  ["plan_showcase_zero_timebox", workspace(), [plan("showcase", "--timebox", "0", "--json")]],
  ["plan_showcase_tiny_timebox_text", workspace(), [plan("showcase", "--timebox", "1")]],
  ["plan_showcase_negative_timebox", workspace(), [plan("showcase", "--timebox", "-5", "--json")]],
  ["plan_showcase_fractional_timebox", workspace(), [plan("showcase", "--timebox", "12.5", "--json")]],
  ["plan_showcase_non_numeric_timebox", workspace(), [plan("showcase", "--timebox", "soon", "--json")]],
  ["plan_showcase_max_items", workspace(), [plan("showcase", "--max-items", "1", "--json")]],
  ["plan_showcase_zero_max_items", workspace(), [plan("showcase", "--max-items", "0", "--json")]],
  ["plan_showcase_zero_max_items_text", workspace(), [plan("showcase", "--max-items", "0")]],
  ["plan_showcase_negative_max_items", workspace(), [plan("showcase", "--max-items", "-1", "--json")]],
  ["plan_showcase_host", workspace(), [plan("showcase", "--host", "codex.cli", "--json")]],
  ["plan_showcase_unknown_host", workspace(), [plan("showcase", "--host", "nowhere.tty", "--json")]],
  ["plan_showcase_changed_path", workspace({ "demo-repo/use-cases/changed.yml": CHANGED }), [plan("showcase", "--changed-path", "src/changed.ts", "--json")]],
  ["plan_showcase_changed_paths_repeated", workspace({ "demo-repo/use-cases/changed.yml": CHANGED }), [plan("showcase", "--changed-path", "src/changed.ts", "--changed-path", "src/other.ts", "--json")]],
  ["plan_showcase_generated_at_is_pinned", workspace(), [uc(["plan", "showcase", ...repo, "--generated-at", "2027-01-02T03:04:05.678Z", "--json"])]],
  ["plan_showcase_malformed_generated_at", workspace(), [uc(["plan", "showcase", ...repo, "--generated-at", "yesterday", "--json"])]],
  ["plan_showcase_empty_generated_at", workspace(), [uc(["plan", "showcase", ...repo, "--generated-at", "", "--json"])]],
  ["plan_showcase_strict_complete", workspace(), [plan("showcase", "--strict", "--json")]],
  ["plan_showcase_strict_incomplete_json", brokenMatrix, [plan("showcase", "--strict", "--json")]],
  ["plan_showcase_strict_incomplete_text", brokenMatrix, [plan("showcase", "--strict")]],
  ["plan_walkthrough_strict_incomplete", brokenMatrix, [plan("walkthrough", "--strict", "--json")]],
  ["plan_showcase_incomplete_without_strict", brokenMatrix, [plan("showcase", "--json")]],
  ["plan_showcase_no_rows_json", noRows, [plan("showcase", "--json")]],
  ["plan_showcase_no_rows_text", noRows, [plan("showcase")]],
  ["plan_walkthrough_no_rows", noRows, [plan("walkthrough", "--json")]],
  ["plan_showcase_unconfigured_workspace", unconfigured, [plan("showcase", "--json")]],
  ["plan_showcase_empty_workspace", empty, [plan("showcase", "--json")]],
  ["plan_showcase_missing_repo_json", empty, [uc(["plan", "showcase", "--repo", `${S}/missing`, ...AT, "--json"])]],
  ["plan_showcase_missing_repo_text", empty, [uc(["plan", "showcase", "--repo", `${S}/missing`, ...AT])]],
  ["plan_showcase_data_root_escape", workspace(), [plan("showcase", "--data-root", `${R}/outside`, "--json")]],
  ["plan_showcase_component_unknown", workspace(), [plan("showcase", "--component", "other", "--json")]],
  ["plan_showcase_unknown_flag", workspace(), [plan("showcase", "--audiance", "reviewer", "--json")]],
  ["plan_showcase_flag_value_swallows_next_flag", workspace(), [uc(["plan", "showcase", ...repo, ...AT, "--audience", "--json"])]],
  ["plan_showcase_damaged_evidence", workspace({ "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "not json\n" }), [plan("showcase", "--json")]],
  ["plan_showcase_damaged_evidence_text", workspace({ "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "not json\n" }), [plan("showcase")]]
];

const cardCases = [
  ["cards_showcase_json", withPlans(), [cards("--plan-file", "plans/showcase.json", "--json")]],
  ["cards_showcase_text", withPlans(), [cards("--plan-file", "plans/showcase.json")]],
  ["cards_walkthrough_json", withPlans(), [cards("--plan-file", "plans/walkthrough.json", "--json")]],
  ["cards_walkthrough_text", withPlans(), [cards("--plan-file", "plans/walkthrough.json")]],
  ["cards_absolute_plan_path", withPlans(), [cards("--plan-file", `${S}/plans/showcase.json`, "--json")]],
  ["cards_missing_plan_file_flag_json", withPlans(), [uc(["plan", "cards", ...repo, "--json"])]],
  ["cards_missing_plan_file_flag_text", withPlans(), [uc(["plan", "cards", ...repo])]],
  ["cards_empty_plan_file_flag", withPlans(), [cards("--plan-file", "", "--json")]],
  ["cards_plan_file_missing_on_disk_json", withPlans(), [cards("--plan-file", "plans/nowhere.json", "--json")]],
  ["cards_plan_file_missing_on_disk_text", withPlans(), [cards("--plan-file", "plans/nowhere.json")]],
  ["cards_plan_file_is_a_directory", withPlans(), [cards("--plan-file", "plans", "--json")]],
  ["cards_plan_file_escapes_the_workspace_json", withPlans(), [cards("--plan-file", "../outside/plan.json", "--json")]],
  ["cards_plan_file_escapes_the_workspace_text", withPlans(), [cards("--plan-file", "../outside/plan.json")]],
  ["cards_plan_file_not_json", withPlans({ "demo-repo/plans/bad.json": "not json\n" }), [cards("--plan-file", "plans/bad.json", "--json")]],
  ["cards_plan_file_not_a_v1_plan", withPlans({ "demo-repo/plans/other.json": '{"schema_version":2}\n' }), [cards("--plan-file", "plans/other.json", "--json")]],
  ["cards_plan_file_is_an_array", withPlans({ "demo-repo/plans/array.json": "[]\n" }), [cards("--plan-file", "plans/array.json", "--json")]],
  ["cards_plan_file_hash_not_a_string", withPlans({ "demo-repo/plans/nohash.json": '{"schema_version":1,"plan_content_hash":1}\n' }), [cards("--plan-file", "plans/nohash.json", "--json")]],
  ["cards_plan_file_placeholder_hash", withPlans({ "demo-repo/plans/placeholder.json": placeholderHash }), [cards("--plan-file", "plans/placeholder.json", "--json")]],
  ["cards_plan_file_hash_mismatch_json", withPlans({ "demo-repo/plans/mismatch.json": mismatchedHash }), [cards("--plan-file", "plans/mismatch.json", "--json")]],
  ["cards_plan_file_hash_mismatch_text", withPlans({ "demo-repo/plans/mismatch.json": mismatchedHash }), [cards("--plan-file", "plans/mismatch.json")]],
  // The two decoder fallbacks the row 3f1 ladder note names.
  ["cards_format_absent_falls_back_to_delivery_kind_json", withPlans({ "demo-repo/plans/noformat.json": withoutFormats }), [cards("--plan-file", "plans/noformat.json", "--json")]],
  ["cards_format_absent_falls_back_to_delivery_kind_text", withPlans({ "demo-repo/plans/noformat.json": withoutFormats }), [cards("--plan-file", "plans/noformat.json")]],
  ["cards_basis_absent_falls_back_to_earlier_run_json", withPlans({ "demo-repo/plans/nobasis.json": withoutBasis }), [cards("--plan-file", "plans/nobasis.json", "--json")]],
  ["cards_basis_absent_falls_back_to_earlier_run_text", withPlans({ "demo-repo/plans/nobasis.json": withoutBasis }), [cards("--plan-file", "plans/nobasis.json")]],
  ["cards_evidence_summary_absent", withPlans({ "demo-repo/plans/nosummary.json": withoutEvidenceSummary }), [cards("--plan-file", "plans/nosummary.json", "--json")]],
  ["cards_unknown_presentation_format", withPlans({ "demo-repo/plans/badformat.json": unknownFormat }), [cards("--plan-file", "plans/badformat.json", "--json")]],
  ["cards_unknown_delivery_kind", withPlans({ "demo-repo/plans/badkind.json": unknownDeliveryKind }), [cards("--plan-file", "plans/badkind.json", "--json")]],
  ["cards_resolved_steps_absent", withPlans({ "demo-repo/plans/nosteps.json": withoutResolvedSteps }), [cards("--plan-file", "plans/nosteps.json", "--json")]],
  ["cards_empty_steps_and_observations", withPlans({ "demo-repo/plans/emptysteps.json": emptyStepsAndObservations }), [cards("--plan-file", "plans/emptysteps.json", "--json")]],
  ["cards_blank_title_falls_back_to_the_id", withPlans({ "demo-repo/plans/blanktitle.json": blankTitle }), [cards("--plan-file", "plans/blanktitle.json", "--json")]],
  ["cards_no_selected_items_json", withPlans({ "demo-repo/plans/noitems.json": noItems }), [cards("--plan-file", "plans/noitems.json", "--json")]],
  ["cards_no_selected_items_text", withPlans({ "demo-repo/plans/noitems.json": noItems }), [cards("--plan-file", "plans/noitems.json")]],
  ["cards_missing_repo", empty, [uc(["plan", "cards", "--repo", `${S}/missing`, "--plan-file", "plans/showcase.json", "--json"])]],
  ["cards_data_root_escape", withPlans(), [cards("--plan-file", "plans/showcase.json", "--data-root", `${R}/outside`, "--json")]],
  ["cards_unknown_flag", withPlans(), [cards("--plan-file", "plans/showcase.json", "--render", "wide", "--json")]],
  ["cards_unreadable_plan_file", withPlans(), [chmod("demo-repo/plans/showcase.json", 0o000), cards("--plan-file", "plans/showcase.json", "--json"), chmod("demo-repo/plans/showcase.json", 0o644)]]
];

const capsuleCases = [
  ["capsule_list_json", capsules(), [capsule("list", "--json")]],
  ["capsule_list_text", capsules(), [capsule("list")]],
  ["capsule_list_no_capsules_json", workspace(), [capsule("list", "--json")]],
  ["capsule_list_no_capsules_text", workspace(), [capsule("list")]],
  ["capsule_list_broken_capsule_json", capsules({ "demo-repo/demo-capsules/broken.yml": CAPSULE_BROKEN }), [capsule("list", "--json")]],
  ["capsule_list_broken_capsule_text", capsules({ "demo-repo/demo-capsules/broken.yml": CAPSULE_BROKEN }), [capsule("list")]],
  ["capsule_list_duplicate_ids", capsules({ "demo-repo/demo-capsules/copy.yml": CAPSULE_TOUR }), [capsule("list", "--json")]],
  ["capsule_list_not_yaml", capsules({ "demo-repo/demo-capsules/notes.txt": "not a capsule\n" }), [capsule("list", "--json")]],
  ["capsule_list_unparsable_yaml", capsules({ "demo-repo/demo-capsules/bad.yml": "schema_version: 1\n\tbad: indent\n" }), [capsule("list", "--json")]],
  ["capsule_list_empty_workspace", empty, [capsule("list", "--json")]],
  ["capsule_list_missing_repo", empty, [uc(["capsule", "list", "--repo", `${S}/missing`, "--json"])]],
  ["capsule_list_data_root_escape", capsules(), [capsule("list", "--data-root", `${R}/outside`, "--json")]],
  ["capsule_list_unknown_flag", capsules(), [capsule("list", "--everything", "--json")]],
  // `--all` is declared by `verify`, so the unknown-flag check (which reads every
  // command's flags) lets it through here and the list still runs.
  ["capsule_list_flag_declared_by_another_command", capsules(), [capsule("list", "--all", "--json")]],

  ["capsule_validate_json", capsules(), [capsule("validate", "--json")]],
  ["capsule_validate_text", capsules(), [capsule("validate")]],
  ["capsule_validate_broken_json", capsules({ "demo-repo/demo-capsules/broken.yml": CAPSULE_BROKEN }), [capsule("validate", "--json")]],
  ["capsule_validate_broken_text", capsules({ "demo-repo/demo-capsules/broken.yml": CAPSULE_BROKEN }), [capsule("validate")]],
  ["capsule_validate_duplicate_ids", capsules({ "demo-repo/demo-capsules/copy.yml": CAPSULE_TOUR }), [capsule("validate", "--json")]],
  ["capsule_validate_no_capsules", workspace(), [capsule("validate", "--json")]],
  ["capsule_validate_missing_repo", empty, [uc(["capsule", "validate", "--repo", `${S}/missing`, "--json"])]],

  ["capsule_plan_json", capsules(), [capsule("plan", "--capsule", "capsule.probe.tour", "--json")]],
  ["capsule_plan_text", capsules(), [capsule("plan", "--capsule", "capsule.probe.tour")]],
  ["capsule_plan_walkthrough_capsule", capsules(), [capsule("plan", "--capsule", "capsule.probe.walkthrough", "--json")]],
  ["capsule_plan_missing_capsule_flag_json", capsules(), [uc(["capsule", "plan", ...repo, "--json"])]],
  ["capsule_plan_missing_capsule_flag_text", capsules(), [uc(["capsule", "plan", ...repo])]],
  ["capsule_plan_empty_capsule_flag", capsules(), [capsule("plan", "--capsule", "", "--json")]],
  ["capsule_plan_unknown_capsule_json", capsules(), [capsule("plan", "--capsule", "capsule.probe.nowhere", "--json")]],
  ["capsule_plan_unknown_capsule_text", capsules(), [capsule("plan", "--capsule", "capsule.probe.nowhere")]],
  ["capsule_plan_integrity_blocked_json", capsules({ "demo-repo/demo-capsules/broken.yml": CAPSULE_BROKEN }), [capsule("plan", "--capsule", "capsule.probe.tour", "--json")]],
  ["capsule_plan_integrity_blocked_text", capsules({ "demo-repo/demo-capsules/broken.yml": CAPSULE_BROKEN }), [capsule("plan", "--capsule", "capsule.probe.tour")]],
  ["capsule_plan_row_not_in_matrix", capsules({ "demo-repo/demo-capsules/unknown.yml": CAPSULE_UNKNOWN_ROW }), [capsule("plan", "--capsule", "capsule.probe.unknown_row", "--json")]],
  ["capsule_plan_broken_matrix", capsules({ "demo-repo/use-cases/broken.yml": "schema_version: 1\nfeature:\n  id: probe.broken\n" }), [capsule("plan", "--capsule", "capsule.probe.tour", "--json")]],
  ["capsule_plan_missing_repo", empty, [uc(["capsule", "plan", "--repo", `${S}/missing`, "--capsule", "capsule.probe.tour", "--json"])]],
  ["capsule_plan_unknown_flag", capsules(), [capsule("plan", "--capsule", "capsule.probe.tour", "--capsuls", "x", "--json")]],
  ["capsule_plan_flag_declared_by_another_command", capsules(), [capsule("plan", "--capsule", "capsule.probe.tour", "--mode", "showcase", "--json")]],

  ["capsule_run_dry_json", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k1", "--json")]],
  ["capsule_run_dry_text", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k1")]],
  ["capsule_run_walkthrough_capsule", capsules(), [capsule("run", "--capsule", "capsule.probe.walkthrough", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k2", "--json")]],
  ["capsule_run_commands_not_executed", capsules({ "demo-repo/demo-capsules/commands.yml": CAPSULE_COMMANDS }), [capsule("run", "--capsule", "capsule.probe.commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k3", "--json")]],
  ["capsule_run_commands_executed_json", capsules({ "demo-repo/demo-capsules/commands.yml": CAPSULE_COMMANDS }), [capsule("run", "--capsule", "capsule.probe.commands", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k4", "--json")]],
  ["capsule_run_commands_executed_text", capsules({ "demo-repo/demo-capsules/commands.yml": CAPSULE_COMMANDS }), [capsule("run", "--capsule", "capsule.probe.commands", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k5")]],
  ["capsule_run_command_fails_json", capsules({ "demo-repo/demo-capsules/fails.yml": capsuleWithCommand("capsule.probe.fails", "/bin/sh", ["-c", "printf out; printf err >&2; exit 3"]) }), [capsule("run", "--capsule", "capsule.probe.fails", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k6", "--json")]],
  ["capsule_run_command_fails_text", capsules({ "demo-repo/demo-capsules/fails.yml": capsuleWithCommand("capsule.probe.fails", "/bin/sh", ["-c", "exit 3"]) }), [capsule("run", "--capsule", "capsule.probe.fails", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k7")]],
  ["capsule_run_command_expected_non_zero", capsules({ "demo-repo/demo-capsules/expected.yml": capsuleWithCommand("capsule.probe.expected", "/bin/sh", ["-c", "exit 3"], { expectedExitCodes: "3" }) }), [capsule("run", "--capsule", "capsule.probe.expected", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k8", "--json")]],
  ["capsule_run_command_not_permitted", capsules({ "demo-repo/demo-capsules/denied.yml": capsuleWithCommand("capsule.probe.denied", "/bin/echo", ["hi"], { permitted: false }) }), [capsule("run", "--capsule", "capsule.probe.denied", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k9", "--json")]],
  ["capsule_run_command_cwd_escape_json", capsules({ "demo-repo/demo-capsules/escape.yml": capsuleWithCommand("capsule.probe.escape", "/bin/echo", ["hi"], { workingDirectory: "../outside" }) }), [capsule("run", "--capsule", "capsule.probe.escape", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k10", "--json")]],
  ["capsule_run_command_cwd_escape_text", capsules({ "demo-repo/demo-capsules/escape.yml": capsuleWithCommand("capsule.probe.escape", "/bin/echo", ["hi"], { workingDirectory: "../outside" }) }), [capsule("run", "--capsule", "capsule.probe.escape", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k11")]],
  ["capsule_run_command_missing_executable", capsules({ "demo-repo/demo-capsules/missing.yml": capsuleWithCommand("capsule.probe.missing", "/nonexistent/tool", ["hi"]) }), [capsule("run", "--capsule", "capsule.probe.missing", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k12", "--json")]],
  ["capsule_run_command_timeout", capsules({ "demo-repo/demo-capsules/slow.yml": capsuleWithCommand("capsule.probe.slow", "/bin/sh", ["-c", "printf started; sleep 5"]) }), [capsule("run", "--capsule", "capsule.probe.slow", "--execute-commands", "--command-timeout-ms", "200", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k13", "--json")]],
  ["capsule_run_timeout_out_of_range", capsules({ "demo-repo/demo-capsules/commands.yml": CAPSULE_COMMANDS }), [capsule("run", "--capsule", "capsule.probe.commands", "--execute-commands", "--command-timeout-ms", "400000", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k14", "--json")]],
  ["capsule_run_timeout_zero", capsules({ "demo-repo/demo-capsules/commands.yml": CAPSULE_COMMANDS }), [capsule("run", "--capsule", "capsule.probe.commands", "--execute-commands", "--command-timeout-ms", "0", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k15", "--json")]],
  ["capsule_run_idempotent_repeat", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k16", "--json"), capsule("run", "--capsule", "capsule.probe.tour", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k16", "--json")]],
  ["capsule_run_retry_after_a_failure", capsules({ "demo-repo/demo-capsules/fails.yml": capsuleWithCommand("capsule.probe.fails", "/bin/sh", ["-c", "exit 3"]) }), [capsule("run", "--capsule", "capsule.probe.fails", "--execute-commands", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k17", "--json"), capsule("run", "--capsule", "capsule.probe.fails", "--execute-commands", "--recorded-at", "2026-06-25T12:00:01.000Z", "--idempotency-key", "k17", "--json")]],
  ["capsule_run_derived_idempotency_key", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--recorded-at", "2026-06-25T12:00:00.000Z", "--json")]],
  ["capsule_run_derived_recorded_at", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--idempotency-key", "k18", "--json")]],
  ["capsule_run_malformed_recorded_at", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--recorded-at", "yesterday", "--idempotency-key", "k19", "--json")]],
  ["capsule_run_missing_capsule_flag_json", capsules(), [uc(["capsule", "run", ...repo, "--json"])]],
  ["capsule_run_missing_capsule_flag_text", capsules(), [uc(["capsule", "run", ...repo])]],
  ["capsule_run_unknown_capsule", capsules(), [capsule("run", "--capsule", "capsule.probe.nowhere", "--json")]],
  ["capsule_run_integrity_blocked", capsules({ "demo-repo/demo-capsules/broken.yml": CAPSULE_BROKEN }), [capsule("run", "--capsule", "capsule.probe.tour", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k20", "--json")]],
  ["capsule_run_row_not_in_matrix", capsules({ "demo-repo/demo-capsules/unknown.yml": CAPSULE_UNKNOWN_ROW }), [capsule("run", "--capsule", "capsule.probe.unknown_row", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k21", "--json")]],
  ["capsule_run_missing_repo", empty, [uc(["capsule", "run", "--repo", `${S}/missing`, "--capsule", "capsule.probe.tour", "--json"])]],
  ["capsule_run_data_root_escape", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--data-root", `${R}/outside`, "--json")]],
  ["capsule_run_unknown_flag", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--dryrun", "--json")]],
  ["capsule_run_then_list_and_validate", capsules(), [capsule("run", "--capsule", "capsule.probe.tour", "--recorded-at", "2026-06-25T12:00:00.000Z", "--idempotency-key", "k22", "--json"), capsule("list", "--json"), capsule("validate", "--json")]]
];

const cases = [...planCases, ...cardCases, ...capsuleCases];

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

const names = new Set();
const recorded = [];
for (const [name, setup, steps] of cases) {
  if (names.has(name)) throw new Error(`duplicate case ${name}`);
  names.add(name);
  const root = realpathSync(mkdtempSync(join(tmpdir(), "uc-plan-capsule-")));
  const sandbox = join(root, "demo-repo");
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "uc-plan-capsule-cwd-")));
  const placeholders = (text) =>
    text.split(sandbox).join("$SANDBOX").split(root).join("$ROOT").split(cwd).join("$CWD").split(repositoryRoot).join("$REPO");
  const concrete = (text) =>
    text.split("$SANDBOX").join(sandbox).split("$ROOT").join(root).split("$CWD").join(cwd).split("$REPO").join(repositoryRoot);
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
// each step of each plan- and capsule-command case.
//
// Regenerate with:
//   pnpm build
//   node UseCasesCLI/Scripts/generate-plan-capsule-corpus.mjs
enum PlanCapsuleGoldenCorpus {
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
const target = join(outputDirectory, "PlanCapsuleGoldenCorpus.swift");
writeFileSync(target, swift);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("PlanCapsuleGoldenCorpus.swift is not ASCII");
}
console.log(`wrote ${recorded.length} cases to ${target}`);
