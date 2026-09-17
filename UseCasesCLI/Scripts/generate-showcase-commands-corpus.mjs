// Regenerates the CLI showcase- and approve-run corpus by running every case
// below through the REAL TypeScript CLI and recording exactly the bytes, exit
// codes and files it produced.
//
//   pnpm build
//   node UseCasesCLI/Scripts/generate-showcase-commands-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCLITests/Entry/ShowcaseCommandsGoldenCorpus.swift
//     For each case: how its sandbox was set up (files), then its STEPS in
//     order — CLI runs, file writes, mode changes, minted key pairs and
//     captures of a previous run's stdout. Every CLI run records its argv,
//     stdout, stderr and exit status; after the last step every file and
//     directory the sandbox holds is recorded (file modes and contents
//     included). Covers row 4e: the twelve `showcase` verbs and `approve-run`,
//     golden, bad and edge, in the JSON and human renderings.
//
// A sandbox is a temporary directory holding `demo-repo` (the workspace),
// `outside` and `home` (HOME for every run). Paths are recorded as
// placeholders: `$ROOT` for the temporary directory, `$SANDBOX` for
// `$ROOT/demo-repo`, `$CWD` for the directory the CLI ran in and `$REPO` for
// this repository.
//
// Every run gets exactly PATH and HOME, plus any variable its step names —
// nothing else from this shell.
//
// KEY MATERIAL IS MINTED PER RUN, never committed: a `keys` step generates an
// ed25519 pair and writes the private PEM, the public PEM and a keyring naming
// it, exactly as tests/blackbox/showcase-flow.test.ts does. The Swift replay
// mints its own pair the same way, so every PEM body and every signature
// differs by construction and is masked on both sides (row 4c precedent). What
// is compared is everything the signature makes possible: the verified tier,
// the capture method, the approval state, the codes and the exit codes.
//
// PLAN FILES are baked into a case's setup as literals, as in the plan/capsule
// corpus: a generated plan does not depend on where its workspace is.
//
// Idempotency keys are pinned on every appending verb, so the run id
// (`run.<key>`) and every event id (`evt.run.<key>.<n>`) are deterministic and
// compared byte for byte. Only `start --adhoc` without a key derives one from
// the clock, and that case passes one.
//
// Normalised by the Swift test on BOTH sides (``ShowcaseCommandsMasking``):
// every PEM body, every `signature.value`, the `jti` nonce and the `iat`,
// `exp` and `created_at` stamps a minted approval request carries, the
// `intent_digest` of an `approval_recorded` or `approval_rejected` event
// (which covers the token, nonce included), and the wall-clock timestamps a
// run without `--recorded-at` stamps. Parser wording is masked as in the
// earlier corpora.
//
// Everything else — plan content hashes, ledger head hashes, evidence digests,
// approval states, assurance tiers, capture methods, diagnostics and exit
// codes — is compared byte for byte.
import { spawnSync } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
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
  ["cli", "commands/showcase"],
  ["cli", "commands/approveRun"],
  ["cli", "trustRender"],
  ["cli", "runtime"],
  ["core", "showcase/appendShowcaseEvent"],
  ["core", "showcase/replayRun"],
  ["core", "showcase/approvalToken"],
  ["core", "showcase/approvalBinding"]
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

const config = (extra = "") => `schema_version: 1
workspace_id: probe
component_id: probe
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
${extra}`;

const CONFIG = config();
const PINNED_CONFIG = config("approval_trust:\n  keyring_path: keyring.json\n");

const NONE_APPROVAL = "    approval_policy:\n      mode: none\n";
// Only a `predefined` policy naming a `user` approver makes a run's approval
// user-required, which is the whole F3 gate: an agent cannot record it, and a
// signed token is the only way through.
const USER_APPROVAL = `    approval_policy:
      mode: predefined
      statement: A human must sign this off.
      requirements:
        - approver_type: user
          minimum_count: 1
`;

function row(id, approval) {
  return `  - id: ${id}
    title: Row ${id}
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so a showcase run can perform it.
    preconditions: [Nothing.]
    trigger: An agent performs it.
    scenarios:
      - id: ${id}.golden_runs
        kind: steps
        steps: [Open the thing., Look at it.]
        observable_outcomes: [It reads as expected.]
    observable_outcomes: [A run can record a verdict for it.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
${approval}`;
}

const shard = (featureId, rows) =>
  `schema_version: 1\nfeature:\n  id: ${featureId}\n  name: Probe\n  summary: Probe.\nuse_cases:\n${rows.join("")}`;

const MATRIX = shard("probe.core", [
  row("probe.core.alpha", NONE_APPROVAL),
  row("probe.core.beta", NONE_APPROVAL)
]);
const USER_MATRIX = shard("probe.core", [
  row("probe.core.alpha", NONE_APPROVAL),
  row("probe.core.signoff", USER_APPROVAL)
]);

const S = "$SANDBOX";
const R = "$ROOT";

// Steps.
const uc = (args, env) => (env ? { kind: "uc", args, env } : { kind: "uc", args });
const write = (path, content) => ({ kind: "write", path, content });
const chmod = (path, mode) => ({ kind: "chmod", path, mode });
// Mint an ed25519 pair: the private PEM, the public PEM, and a keyring naming
// the public half under `keyId`.
const keys = (keyId = "probe-signer") => ({
  kind: "keys",
  keyId,
  privatePath: "signer.key",
  publicPath: "demo-repo/signer.pub",
  keyringPath: "demo-repo/keyring.json"
});
// Write the LAST run's stdout to a file, so a minted approval request can be
// signed. Relative, because a case's step list is assembled from helpers.
const capture = (path) => ({ kind: "capture", path });

const repo = ["--repo", S];
const showcase = (verb, ...rest) => uc(["showcase", verb, ...repo, ...rest]);
const approveRun = (...rest) => uc(["approve-run", ...rest]);

const AT = ["--generated-at", "2026-06-25T12:00:00.000Z"];
const startPlan = (...rest) =>
  showcase("start", "--plan-file", "plans/showcase.json", "--idempotency-key", "s1", "--recorded-at", "2026-06-25T12:00:00.000Z", ...rest);
const observe = (item, ...rest) =>
  showcase("record-observation", "--run", "run.s1", "--item", item, "--text", "Seen it work.", "--idempotency-key", `o-${item}`, "--recorded-at", "2026-06-25T12:01:00.000Z", ...rest);
const verdict = (item, value, ...rest) =>
  showcase("record-verdict", "--run", "run.s1", "--item", item, "--verdict", value, "--idempotency-key", `v-${item}`, "--recorded-at", "2026-06-25T12:02:00.000Z", ...rest);
const finish = (...rest) =>
  showcase("finish", "--run", "run.s1", "--idempotency-key", "f1", "--recorded-at", "2026-06-25T12:03:00.000Z", ...rest);
const status = (...rest) => showcase("status", "--run", "run.s1", ...rest);
const requestApproval = (...rest) => showcase("request-approval", "--run", "run.s1", ...rest);

// ---------------------------------------------------------------------------
// Plan files, computed once from the real planner

function scratchPlan(files, extraArguments = []) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "uc-showcase-seed-")));
  try {
    for (const [path, content] of Object.entries(files)) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), content);
    }
    const sandbox = join(root, "demo-repo");
    const result = spawnSync(
      process.execPath,
      [cliEntry, "plan", "showcase", "--repo", sandbox, ...AT, ...extraArguments, "--json"],
      { cwd: root, encoding: "utf8", env: { PATH: process.env.PATH, HOME: root } }
    );
    const parsed = result.stdout ? JSON.parse(result.stdout) : null;
    if (!parsed?.data?.plan) {
      throw new Error(`seed plan failed (${result.status}): ${result.stdout}${result.stderr}`);
    }
    return `${JSON.stringify(parsed.data.plan, null, 2)}\n`;
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const PLAN = scratchPlan({ "demo-repo/use-cases.yml": CONFIG, "demo-repo/use-cases/probe.yml": MATRIX });
const USER_PLAN = scratchPlan({ "demo-repo/use-cases.yml": CONFIG, "demo-repo/use-cases/probe.yml": USER_MATRIX });
const items = (plan) => JSON.parse(plan).selected_items.map((item) => item.plan_item_id);
const ITEMS = items(PLAN);
const USER_ITEMS = items(USER_PLAN);

function workspace(extra = {}) {
  return {
    files: {
      "demo-repo/use-cases.yml": CONFIG,
      "demo-repo/use-cases/probe.yml": MATRIX,
      "demo-repo/plans/showcase.json": PLAN,
      ...extra
    }
  };
}

/// A workspace whose plan needs a human sign-off, with `approval_trust`
/// pinned to the keyring a `keys` step writes.
function userWorkspace(extra = {}) {
  return {
    files: {
      "demo-repo/use-cases.yml": PINNED_CONFIG,
      "demo-repo/use-cases/probe.yml": USER_MATRIX,
      "demo-repo/plans/showcase.json": USER_PLAN,
      ...extra
    }
  };
}

/// The same, with no `approval_trust` pin: caller-supplied trust only.
function unpinnedUserWorkspace(extra = {}) {
  return {
    files: {
      "demo-repo/use-cases.yml": CONFIG,
      "demo-repo/use-cases/probe.yml": USER_MATRIX,
      "demo-repo/plans/showcase.json": USER_PLAN,
      ...extra
    }
  };
}

const empty = { files: {} };
const DAMAGED_LEDGER = { "demo-repo/showcase-runs/run.broken/events.jsonl": "not json\n" };

/// Observe and judge every item of a plan, so the run can finish.
const performAll = (planItems, value = "pass") =>
  planItems.flatMap((item) => [observe(item), verdict(item, value)]);

/// The whole golden run: start, perform, finish.
const wholeRun = (planItems) => [startPlan("--json"), ...performAll(planItems), finish("--json")];

// ---------------------------------------------------------------------------
// Cases

const startCases = [
  ["start_from_plan_file_json", workspace(), [startPlan("--json")]],
  ["start_from_plan_file_text", workspace(), [startPlan()]],
  ["start_idempotent_repeat", workspace(), [startPlan("--json"), startPlan("--json")]],
  ["start_same_plan_new_key", workspace(), [startPlan("--json"), showcase("start", "--plan-file", "plans/showcase.json", "--idempotency-key", "s2", "--recorded-at", "2026-06-25T12:00:00.000Z", "--json")]],
  ["start_idempotency_conflict", workspace(), [startPlan("--json"), showcase("start", "--plan-file", "plans/showcase.json", "--idempotency-key", "s1", "--recorded-at", "2026-06-25T12:30:00.000Z", "--json")]],
  ["start_derived_idempotency_key_from_plan", workspace(), [showcase("start", "--plan-file", "plans/showcase.json", "--recorded-at", "2026-06-25T12:00:00.000Z", "--json")]],
  ["start_adhoc_json", workspace(), [showcase("start", "--adhoc", "--select", "probe.core.alpha", ...AT, "--idempotency-key", "a1", "--recorded-at", "2026-06-25T12:00:00.000Z", "--json")]],
  ["start_adhoc_text", workspace(), [showcase("start", "--adhoc", "--select", "probe.core.alpha", ...AT, "--idempotency-key", "a1", "--recorded-at", "2026-06-25T12:00:00.000Z")]],
  ["start_adhoc_audience_and_timebox", workspace(), [showcase("start", "--adhoc", "--select", "probe.core.beta", "--audience", "stakeholder", "--timebox", "120", ...AT, "--idempotency-key", "a2", "--recorded-at", "2026-06-25T12:00:00.000Z", "--json")]],
  ["start_adhoc_unknown_row_json", workspace(), [showcase("start", "--adhoc", "--select", "probe.core.nowhere", ...AT, "--idempotency-key", "a3", "--json")]],
  ["start_adhoc_unknown_row_text", workspace(), [showcase("start", "--adhoc", "--select", "probe.core.nowhere", ...AT, "--idempotency-key", "a3")]],
  ["start_adhoc_without_select", workspace(), [showcase("start", "--adhoc", ...AT, "--json")]],
  ["start_select_without_adhoc", workspace(), [showcase("start", "--select", "probe.core.alpha", ...AT, "--json")]],
  ["start_without_plan_or_adhoc_json", workspace(), [showcase("start", "--json")]],
  ["start_without_plan_or_adhoc_text", workspace(), [showcase("start")]],
  ["start_plan_file_escapes_the_workspace", workspace(), [showcase("start", "--plan-file", "../outside/plan.json", "--idempotency-key", "s1", "--json")]],
  ["start_plan_file_missing", workspace(), [showcase("start", "--plan-file", "plans/nowhere.json", "--idempotency-key", "s1", "--json")]],
  ["start_plan_file_not_json", workspace({ "demo-repo/plans/bad.json": "not json\n" }), [showcase("start", "--plan-file", "plans/bad.json", "--idempotency-key", "s1", "--json")]],
  ["start_plan_file_hash_mismatch", workspace({ "demo-repo/plans/mismatch.json": PLAN.replace(/"plan_content_hash": "sha256:[0-9a-f]{64}"/, `"plan_content_hash": "sha256:${"a".repeat(64)}"`) }), [showcase("start", "--plan-file", "plans/mismatch.json", "--idempotency-key", "s1", "--json")]],
  ["start_against_damaged_ledger", workspace(DAMAGED_LEDGER), [showcase("start", "--plan-file", "plans/showcase.json", "--idempotency-key", "broken", "--recorded-at", "2026-06-25T12:00:00.000Z", "--json")]],
  ["start_missing_repo", empty, [uc(["showcase", "start", "--repo", `${S}/missing`, "--plan-file", "plans/showcase.json", "--json"])]],
  ["start_data_root_escape", workspace(), [showcase("start", "--plan-file", "plans/showcase.json", "--data-root", `${R}/outside`, "--json")]],
  ["start_unknown_flag", workspace(), [showcase("start", "--plan-file", "plans/showcase.json", "--plan-fileee", "x", "--json")]]
];

const recordingCases = [
  ["observation_json", workspace(), [startPlan("--json"), observe(ITEMS[0], "--json")]],
  ["observation_text", workspace(), [startPlan("--json"), observe(ITEMS[0])]],
  ["observation_idempotent_repeat", workspace(), [startPlan("--json"), observe(ITEMS[0], "--json"), observe(ITEMS[0], "--json")]],
  ["observation_secret_is_redacted", workspace(), [startPlan("--json"), showcase("record-observation", "--run", "run.s1", "--item", ITEMS[0], "--text", "token=ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAA and sk-abcdefghijklmnop", "--idempotency-key", "o-secret", "--recorded-at", "2026-06-25T12:01:00.000Z", "--json")]],
  ["observation_unknown_item", workspace(), [startPlan("--json"), observe("item.probe.core.nowhere", "--json")]],
  ["observation_unknown_run", workspace(), [showcase("record-observation", "--run", "run.nowhere", "--item", ITEMS[0], "--text", "x", "--idempotency-key", "o1", "--json")]],
  ["observation_missing_flags_json", workspace(), [showcase("record-observation", "--run", "run.s1", "--json")]],
  ["observation_missing_flags_text", workspace(), [showcase("record-observation", "--run", "run.s1")]],
  ["observation_invalid_run_id", workspace(), [showcase("record-observation", "--run", "RUN.S1", "--item", ITEMS[0], "--text", "x", "--json")]],
  ["observation_invalid_item_id", workspace(), [showcase("record-observation", "--run", "run.s1", "--item", "../outside", "--text", "x", "--json")]],
  ["observation_damaged_ledger", workspace(DAMAGED_LEDGER), [showcase("record-observation", "--run", "run.broken", "--item", ITEMS[0], "--text", "x", "--idempotency-key", "o1", "--json")]],
  ["observation_recorded_at_defaults", workspace(), [startPlan("--json"), showcase("record-observation", "--run", "run.s1", "--item", ITEMS[0], "--text", "x", "--idempotency-key", "o1", "--json")]],

  ["verdict_pass_json", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "pass", "--json")]],
  ["verdict_pass_text", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "pass")]],
  ["verdict_fail_json", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "fail", "--json")]],
  ["verdict_blocked", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "blocked", "--json")]],
  ["verdict_unknown_value", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "maybe", "--json")]],
  ["verdict_actor_user", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "pass", "--actor", "user", "--json")]],
  ["verdict_actor_script", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "pass", "--actor", "script", "--json")]],
  ["verdict_actor_unknown", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "pass", "--actor", "robot", "--json")]],
  ["verdict_without_observation_json", workspace(), [startPlan("--json"), verdict(ITEMS[0], "pass", "--json")]],
  ["verdict_without_observation_text", workspace(), [startPlan("--json"), verdict(ITEMS[0], "pass")]],
  ["verdict_missing_flags", workspace(), [showcase("record-verdict", "--run", "run.s1", "--item", ITEMS[0], "--json")]],
  ["verdict_invalid_ids", workspace(), [showcase("record-verdict", "--run", "run.s1", "--item", "Item.Bad", "--verdict", "pass", "--json")]],
  ["verdict_unknown_run", workspace(), [showcase("record-verdict", "--run", "run.nowhere", "--item", ITEMS[0], "--verdict", "pass", "--json")]],

  ["decide_waive_json", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "fail", "--json"), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.3", "--decision", "waive", "--reason", "Known gap, tracked.", "--idempotency-key", "d1", "--recorded-at", "2026-06-25T12:02:30.000Z", "--json")]],
  ["decide_waive_text", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "fail", "--json"), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.3", "--decision", "waive", "--reason", "Known gap, tracked.", "--idempotency-key", "d1", "--recorded-at", "2026-06-25T12:02:30.000Z")]],
  ["decide_on_a_passing_verdict", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "pass", "--json"), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.3", "--decision", "waive", "--reason", "No.", "--idempotency-key", "d1", "--json")]],
  ["decide_on_an_observation", workspace(), [startPlan("--json"), observe(ITEMS[0]), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.2", "--decision", "waive", "--reason", "No.", "--idempotency-key", "d1", "--json")]],
  ["decide_unknown_event", workspace(), [startPlan("--json"), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.99", "--decision", "waive", "--reason", "No.", "--idempotency-key", "d1", "--json")]],
  ["decide_unknown_decision", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "fail", "--json"), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.3", "--decision", "shrug", "--reason", "No.", "--idempotency-key", "d1", "--json")]],
  ["decide_missing_flags", workspace(), [showcase("decide", "--run", "run.s1", "--json")]],
  ["decide_reason_secret_is_not_redacted", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "fail", "--json"), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.3", "--decision", "waive", "--reason", "token=ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAA", "--idempotency-key", "d1", "--recorded-at", "2026-06-25T12:02:30.000Z", "--json")]],

  ["pause_json", workspace(), [startPlan("--json"), showcase("pause", "--run", "run.s1", "--idempotency-key", "p1", "--recorded-at", "2026-06-25T12:02:45.000Z", "--json")]],
  ["pause_text", workspace(), [startPlan("--json"), showcase("pause", "--run", "run.s1", "--idempotency-key", "p1", "--recorded-at", "2026-06-25T12:02:45.000Z")]],
  ["pause_default_reason", workspace(), [startPlan("--json"), showcase("pause", "--run", "run.s1", "--idempotency-key", "p1", "--recorded-at", "2026-06-25T12:02:45.000Z", "--json"), status("--json")]],
  ["pause_then_resume", workspace(), [startPlan("--json"), showcase("pause", "--run", "run.s1", "--reason", "Coffee.", "--idempotency-key", "p1", "--recorded-at", "2026-06-25T12:02:45.000Z", "--json"), showcase("resume", "--run", "run.s1", "--reason", "Back.", "--idempotency-key", "r1", "--recorded-at", "2026-06-25T12:02:50.000Z", "--json")]],
  ["resume_without_pause", workspace(), [startPlan("--json"), showcase("resume", "--run", "run.s1", "--idempotency-key", "r1", "--recorded-at", "2026-06-25T12:02:50.000Z", "--json")]],
  ["pause_missing_run", workspace(), [showcase("pause", "--json")]],
  ["resume_missing_run", workspace(), [showcase("resume", "--json")]],
  ["pause_invalid_run_id", workspace(), [showcase("pause", "--run", "../outside", "--json")]],

  ["correct_json", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "fail", "--json"), showcase("correct", "--run", "run.s1", "--target-event", "evt.run.s1.3", "--verdict", "pass", "--reason", "Misread the output.", "--idempotency-key", "c1", "--recorded-at", "2026-06-25T12:04:45.000Z", "--json")]],
  ["correct_text", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "fail", "--json"), showcase("correct", "--run", "run.s1", "--target-event", "evt.run.s1.3", "--verdict", "pass", "--reason", "Misread the output.", "--idempotency-key", "c1", "--recorded-at", "2026-06-25T12:04:45.000Z")]],
  ["correct_an_observation", workspace(), [startPlan("--json"), observe(ITEMS[0]), showcase("correct", "--run", "run.s1", "--target-event", "evt.run.s1.2", "--verdict", "pass", "--reason", "No.", "--idempotency-key", "c1", "--json")]],
  ["correct_missing_flags", workspace(), [showcase("correct", "--run", "run.s1", "--json")]],

  ["finish_passed_json", workspace(), [...wholeRun(ITEMS)]],
  ["finish_passed_text", workspace(), [startPlan("--json"), ...performAll(ITEMS), finish()]],
  ["finish_with_undecided_failure_json", workspace(), [startPlan("--json"), ...performAll(ITEMS, "fail"), finish("--json")]],
  ["finish_with_undecided_failure_text", workspace(), [startPlan("--json"), ...performAll(ITEMS, "fail"), finish()]],
  ["finish_with_pending_items", workspace(), [startPlan("--json"), observe(ITEMS[0]), verdict(ITEMS[0], "pass"), finish("--json")]],
  ["finish_idempotent_repeat", workspace(), [...wholeRun(ITEMS), finish("--json")]],
  ["finish_missing_run", workspace(), [showcase("finish", "--json")]],
  ["finish_unknown_run", workspace(), [showcase("finish", "--run", "run.nowhere", "--idempotency-key", "f1", "--json")]],
  ["finish_invalid_run_id", workspace(), [showcase("finish", "--run", "Run.S1", "--json")]],

  ["status_json", workspace(), [...wholeRun(ITEMS), status("--json")]],
  ["status_text", workspace(), [...wholeRun(ITEMS), status()]],
  ["status_before_finish_text", workspace(), [startPlan("--json"), observe(ITEMS[0]), status()]],
  ["status_unknown_run_json", workspace(), [status("--json")]],
  ["status_unknown_run_text", workspace(), [status()]],
  ["status_damaged_ledger", workspace(DAMAGED_LEDGER), [showcase("status", "--run", "run.broken", "--json")]],
  ["status_missing_run", workspace(), [showcase("status", "--json")]],
  ["status_invalid_run_id", workspace(), [showcase("status", "--run", "../outside", "--json")]],
  ["status_missing_repo", empty, [uc(["showcase", "status", "--repo", `${S}/missing`, "--run", "run.s1", "--json"])]],
  ["status_keyring_unreadable", workspace(), [...wholeRun(ITEMS), status("--keyring", "nowhere.json", "--json")]],
  ["status_public_key_unreadable", workspace(), [...wholeRun(ITEMS), status("--public-key", "nowhere.pem", "--json")]]
];

const approvalCases = [
  // A run whose plan needs no human: an agent's approval is recorded.
  ["approve_not_required_json", workspace(), [...wholeRun(ITEMS), showcase("approve", "--run", "run.s1", "--statement", "Looks right.", "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")]],
  ["approve_not_required_text", workspace(), [...wholeRun(ITEMS), showcase("approve", "--run", "run.s1", "--statement", "Looks right.", "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z")]],
  ["approve_before_finish", workspace(), [startPlan("--json"), showcase("approve", "--run", "run.s1", "--statement", "Too soon.", "--idempotency-key", "ap1", "--json")]],
  ["approve_missing_statement", workspace(), [showcase("approve", "--run", "run.s1", "--json")]],
  ["approve_missing_run", workspace(), [showcase("approve", "--statement", "x", "--json")]],
  ["approve_invalid_run_id", workspace(), [showcase("approve", "--run", "RUN", "--statement", "x", "--json")]],
  ["approve_failed_run", workspace(), [startPlan("--json"), ...performAll(ITEMS, "fail"), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.3", "--decision", "waive", "--reason", "Known.", "--idempotency-key", "d1", "--recorded-at", "2026-06-25T12:02:30.000Z", "--json"), showcase("decide", "--run", "run.s1", "--verdict-event", "evt.run.s1.5", "--decision", "waive", "--reason", "Known.", "--idempotency-key", "d2", "--recorded-at", "2026-06-25T12:02:31.000Z", "--json"), finish("--json"), showcase("approve", "--run", "run.s1", "--statement", "Waived.", "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")]],
  ["reject_json", workspace(), [...wholeRun(ITEMS), showcase("reject", "--run", "run.s1", "--statement", "Not good enough.", "--idempotency-key", "rj1", "--recorded-at", "2026-06-25T12:04:30.000Z", "--json")]],
  ["reject_text", workspace(), [...wholeRun(ITEMS), showcase("reject", "--run", "run.s1", "--statement", "Not good enough.", "--idempotency-key", "rj1", "--recorded-at", "2026-06-25T12:04:30.000Z")]],
  ["reject_missing_statement", workspace(), [showcase("reject", "--run", "run.s1", "--json")]],
  ["reject_actor_agent", workspace(), [...wholeRun(ITEMS), showcase("reject", "--run", "run.s1", "--statement", "No.", "--actor", "agent", "--idempotency-key", "rj1", "--recorded-at", "2026-06-25T12:04:30.000Z", "--json")]],

  // A run whose plan names a user approver: the F3 gate.
  ["user_required_approve_without_token_json", userWorkspace(), [...wholeRun(USER_ITEMS), showcase("approve", "--run", "run.s1", "--statement", "Me again.", "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")]],
  ["user_required_approve_without_token_text", userWorkspace(), [...wholeRun(USER_ITEMS), showcase("approve", "--run", "run.s1", "--statement", "Me again.", "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z")]],
  ["user_required_reject_without_token", userWorkspace(), [...wholeRun(USER_ITEMS), showcase("reject", "--run", "run.s1", "--statement", "No.", "--idempotency-key", "rj1", "--recorded-at", "2026-06-25T12:04:30.000Z", "--json")]],
  ["user_required_status_is_pending", userWorkspace(), [...wholeRun(USER_ITEMS), status()]],
  ["request_approval_json", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json")]],
  ["request_approval_text", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval()]],
  ["request_approval_before_finish", userWorkspace(), [startPlan("--json"), requestApproval("--json")]],
  ["request_approval_unknown_run", userWorkspace(), [requestApproval("--json")]],
  ["request_approval_missing_run", userWorkspace(), [showcase("request-approval", "--json")]],
  ["request_approval_invalid_run_id", userWorkspace(), [showcase("request-approval", "--run", "../outside", "--json")]],

  ["signed_approval_json", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Signed off.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")
  ]],
  ["signed_approval_text_and_status", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Signed off.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z"),
    status()
  ]],
  ["signed_approval_nonce_is_burned", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Signed off.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Again.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap2", "--recorded-at", "2026-06-25T12:05:00.000Z", "--json")
  ]],
  ["signed_rejection", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--decision", "rejected", "--out", `${S}/token.json`, "--json"),
    showcase("reject", "--run", "run.s1", "--statement", "Rejected after review.", "--approval-token", `${S}/token.json`, "--idempotency-key", "rj1", "--recorded-at", "2026-06-25T12:04:30.000Z", "--json")
  ]],
  ["signed_approval_decision_mismatch", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--decision", "rejected", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Mismatched.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")
  ]],
  ["signed_approval_with_known_gaps", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--decision", "approved_with_known_gaps", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Gaps known.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")
  ]],
  ["signed_approval_automation_method_is_below_the_floor", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--assurance-method", "automation", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Automated.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")
  ]],
  ["signed_approval_unpinned_workspace_needs_a_flag", unpinnedUserWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Signed off.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")
  ]],
  ["signed_approval_caller_supplied_keyring_is_a_diagnostic", unpinnedUserWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Signed off.", "--approval-token", `${S}/token.json`, "--keyring", `${S}/keyring.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")
  ]],
  ["signed_approval_caller_supplied_public_key", unpinnedUserWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Signed off.", "--approval-token", `${S}/token.json`, "--public-key", `${S}/signer.pub`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")
  ]],
  ["signed_approval_pinned_narrowed_by_another_key", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json"),
    write("demo-repo/other.json", `${JSON.stringify({ keyring_schema_id: "ucase-public-key-registry-v1", keys: [{ key_id: "someone-else", algorithm: "ed25519", public_key: "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAGb9ECWmEzf6FQbrBZ9w7lshQhqowtrbLDFw4rXAxZuE=\n-----END PUBLIC KEY-----\n", valid_from: "2026-01-01T00:00:00Z", valid_until: null, status: "active", max_assurance_tier: "trusted_host_user_presence" }] }, null, 2)}\n`),
    showcase("approve", "--run", "run.s1", "--statement", "Narrowed away.", "--approval-token", `${S}/token.json`, "--keyring", `${S}/other.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json")
  ]],
  ["approve_token_unreadable", userWorkspace(), [...wholeRun(USER_ITEMS), showcase("approve", "--run", "run.s1", "--statement", "x", "--approval-token", `${S}/nowhere.json`, "--idempotency-key", "ap1", "--json")]],
  ["approve_token_not_json", userWorkspace({ "demo-repo/token.json": "not json\n" }), [...wholeRun(USER_ITEMS), showcase("approve", "--run", "run.s1", "--statement", "x", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--json")]],
  ["approve_token_keyring_unreadable", unpinnedUserWorkspace({ "demo-repo/token.json": '{"jti":"approval.x"}\n' }), [...wholeRun(USER_ITEMS), showcase("approve", "--run", "run.s1", "--statement", "x", "--approval-token", `${S}/token.json`, "--keyring", `${S}/nowhere.json`, "--idempotency-key", "ap1", "--json")]],
  ["approve_token_public_key_unreadable", unpinnedUserWorkspace({ "demo-repo/token.json": '{"jti":"approval.x"}\n' }), [...wholeRun(USER_ITEMS), showcase("approve", "--run", "run.s1", "--statement", "x", "--approval-token", `${S}/token.json`, "--public-key", `${S}/nowhere.pem`, "--idempotency-key", "ap1", "--json")]],
  ["approve_token_signer_not_pinned", userWorkspace({ "demo-repo/token.json": '{"approval_token_schema":"ucase-approval-token-v1","jti":"approval.x","signature":{"alg":"ed25519","key_id":"stranger","value":"AAAA"}}\n' }), [
    keys(), ...wholeRun(USER_ITEMS), showcase("approve", "--run", "run.s1", "--statement", "x", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--json")
  ]],
  ["approve_webauthn_token_needs_a_pinned_credential", unpinnedUserWorkspace({ "demo-repo/token.json": '{"approval_token_schema":"ucase-approval-token-v1","jti":"approval.x","signature":{"alg":"webauthn","credential_id":"cred"}}\n' }), [
    keys(), ...wholeRun(USER_ITEMS), showcase("approve", "--run", "run.s1", "--statement", "x", "--approval-token", `${S}/token.json`, "--keyring", `${S}/keyring.json`, "--idempotency-key", "ap1", "--json")
  ]],
  ["status_reads_an_embedded_token", userWorkspace(), [
    keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json"),
    showcase("approve", "--run", "run.s1", "--statement", "Signed off.", "--approval-token", `${S}/token.json`, "--idempotency-key", "ap1", "--recorded-at", "2026-06-25T12:04:00.000Z", "--json"),
    status("--json"),
    status("--keyring", `${S}/keyring.json`, "--json")
  ]]
];

const approveRunCases = [
  ["approve_run_missing_request", empty, [approveRun("--key-id", "k", "--json")]],
  ["approve_run_missing_key_id", empty, [approveRun("--request", `${S}/request.json`, "--json")]],
  ["approve_run_missing_everything_text", empty, [approveRun()]],
  ["approve_run_request_unreadable", empty, [approveRun("--request", `${S}/nowhere.json`, "--key-id", "k", "--json")]],
  ["approve_run_request_not_json", { files: { "demo-repo/request.json": "not json\n" } }, [approveRun("--request", `${S}/request.json`, "--key-id", "k", "--json")]],
  ["approve_run_request_malformed", { files: { "demo-repo/request.json": '{"approval_request_schema":"other"}\n' } }, [approveRun("--request", `${S}/request.json`, "--key-id", "k", "--json")]],
  ["approve_run_request_is_an_array", { files: { "demo-repo/request.json": "[]\n" } }, [approveRun("--request", `${S}/request.json`, "--key-id", "k", "--json")]],
  ["approve_run_unknown_decision", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-id", "k", "--decision", "maybe", "--json")]],
  ["approve_run_unknown_assurance_method", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-id", "k", "--assurance-method", "vibes", "--json")]],
  ["approve_run_webauthn_method_without_an_assertion", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-id", "k", "--assurance-method", "webauthn", "--json")]],
  ["approve_run_no_key", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-id", "k", "--json")]],
  ["approve_run_no_key_text", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-id", "k")]],
  ["approve_run_key_file_unreadable", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-file", `${R}/nowhere.key`, "--key-id", "k", "--json")]],
  ["approve_run_key_file_is_not_a_key", userWorkspace({ "demo-repo/not.key": "not a key\n" }), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-file", `${S}/not.key`, "--key-id", "k", "--json")]],
  ["approve_run_key_env_empty", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-env", "UC_PROBE_KEY", "--key-id", "k", "--json")]],
  ["approve_run_key_env_unset", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-env", "UC_PROBE_MISSING", "--key-id", "k", "--json")]],
  ["approve_run_webauthn_assertion_with_a_key_file", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--webauthn-assertion", `${S}/assertion.json`, "--key-file", `${R}/signer.key`, "--json")]],
  ["approve_run_webauthn_assertion_unreadable", userWorkspace(), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--webauthn-assertion", `${S}/nowhere.json`, "--json")]],
  ["approve_run_webauthn_assertion_malformed", userWorkspace({ "demo-repo/assertion.json": '{"credential_id":"cred"}\n' }), [...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--webauthn-assertion", `${S}/assertion.json`, "--json")]],
  ["approve_run_inline_json", userWorkspace(), [keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--json")]],
  ["approve_run_inline_text", userWorkspace(), [keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer")]],
  ["approve_run_out_writes_the_token", userWorkspace(), [keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`, "--json")]],
  ["approve_run_out_text", userWorkspace(), [keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--out", `${S}/token.json`)]],
  ["approve_run_assurance_methods", userWorkspace(), [keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--assurance-method", "automation", "--json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--assurance-method", "same_channel", "--json"),
    approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--assurance-method", "os_presence", "--json")
  ]],
  ["approve_run_key_env_holds_the_key", userWorkspace(), [keys(), ...wholeRun(USER_ITEMS), requestApproval("--json"), capture("demo-repo/request.json"), { kind: "key_env", variable: "UC_PROBE_KEY", path: "signer.key" }, approveRun("--request", `${S}/request.json`, "--key-env", "UC_PROBE_KEY", "--key-id", "probe-signer", "--json")]],
  ["approve_run_unknown_flag", empty, [approveRun("--request", `${S}/request.json`, "--key-id", "k", "--sign-it", "--json")]],
  ["approve_run_needs_no_workspace", { files: { "demo-repo/request.json": '{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.s1","finish_event_id":"evt.run.s1.1","plan_content_hash":"sha256:' + "b".repeat(64) + '","ledger_head_hash":"sha256:' + "c".repeat(64) + '","evidence_digest":"sha256:' + "d".repeat(64) + '","git_commit":"unknown","ci_freshness_digest":"sha256:' + "e".repeat(64) + '"},"jti":"approval.fixed-nonce","iat":"2026-06-25T12:00:00.000Z","exp":"2026-06-25T12:15:00.000Z"}\n' } }, [keys(), approveRun("--request", `${S}/request.json`, "--key-file", `${R}/signer.key`, "--key-id", "probe-signer", "--json")]]
];

const cases = [...startCases, ...recordingCases, ...approvalCases, ...approveRunCases];

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

/// The keyring a `keys` step writes, formatted exactly as the Swift replay
/// formats its own.
function keyringDocument(keyId, publicPem) {
  return `${JSON.stringify(
    {
      keyring_schema_id: "ucase-public-key-registry-v1",
      keys: [
        {
          key_id: keyId,
          algorithm: "ed25519",
          public_key: publicPem,
          valid_from: "2026-01-01T00:00:00Z",
          valid_until: null,
          status: "active",
          max_assurance_tier: "trusted_host_user_presence"
        }
      ]
    },
    null,
    2
  )}\n`;
}

const names = new Set();
const recorded = [];
for (const [name, setup, steps] of cases) {
  if (names.has(name)) throw new Error(`duplicate case ${name}`);
  names.add(name);
  const root = realpathSync(mkdtempSync(join(tmpdir(), "uc-showcase-")));
  const sandbox = join(root, "demo-repo");
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "uc-showcase-cwd-")));
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
        const result = spawnSync(process.execPath, [cliEntry, ...step.args.map(concrete)], {
          cwd,
          encoding: "utf8",
          env: { ...environment, ...(step.env ?? {}) }
        });
        runs.push({ stdout: placeholders(result.stdout), stderr: placeholders(result.stderr), status: result.status });
      } else if (step.kind === "write") {
        mkdirSync(dirname(join(root, step.path)), { recursive: true });
        writeFileSync(join(root, step.path), step.content);
      } else if (step.kind === "chmod") {
        chmodSync(join(root, step.path), step.mode);
      } else if (step.kind === "keys") {
        const { publicKey, privateKey } = generateKeyPairSync("ed25519");
        const publicPem = publicKey.export({ type: "spki", format: "pem" }).toString();
        const privatePem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
        writeFileSync(join(root, step.privatePath), privatePem, { mode: 0o600 });
        mkdirSync(dirname(join(root, step.publicPath)), { recursive: true });
        writeFileSync(join(root, step.publicPath), publicPem);
        writeFileSync(join(root, step.keyringPath), keyringDocument(step.keyId, publicPem));
      } else if (step.kind === "capture") {
        const captured = runs[runs.length - 1];
        if (!captured) throw new Error(`${name}: capture before any run`);
        mkdirSync(dirname(join(root, step.path)), { recursive: true });
        writeFileSync(join(root, step.path), concrete(captured.stdout));
      } else if (step.kind === "key_env") {
        environment[step.variable] = readFileSync(join(root, step.path), "utf8");
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
// each step of each showcase- and approve-run case.
//
// Regenerate with:
//   pnpm build
//   node UseCasesCLI/Scripts/generate-showcase-commands-corpus.mjs
enum ShowcaseCommandsGoldenCorpus {
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
const target = join(outputDirectory, "ShowcaseCommandsGoldenCorpus.swift");
writeFileSync(target, swift);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("ShowcaseCommandsGoldenCorpus.swift is not ASCII");
}
console.log(`wrote ${recorded.length} cases to ${target}`);
