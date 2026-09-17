// Regenerates the CLI marker-command corpus by running every case below
// through the REAL TypeScript CLI and recording exactly the bytes, exit codes
// and files it produced.
//
//   pnpm build
//   node UseCasesCLI/Scripts/generate-marker-commands-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCLITests/Entry/MarkerCommandsGoldenCorpus.swift
//     For each case: how its sandbox was set up (files and whether it is a git
//     repository), then its STEPS in order — CLI runs, file writes, edits and
//     removals, and git commands. Every CLI run records its argv, extra
//     environment, stdout, stderr and exit status; after the last step every
//     file and directory the sandbox holds is recorded (file modes and contents
//     included, `.git` left out). Covers row 4c: `bind`, `unbind`, `rebind`,
//     `scan`, `impact`, `prove`, `verify`, `validate-ledger`, `keygen` and
//     `recover`, golden, bad and edge, in the JSON and human renderings.
//
// A sandbox is a temporary directory holding `demo-repo` (the workspace),
// `outside` (keys, results files and other inputs kept out of the workspace)
// and `home` (HOME for every run, holding a FIXED run key so attestations are
// stable). Paths are recorded as placeholders: `$ROOT` for the temporary
// directory, `$SANDBOX` for `$ROOT/demo-repo`, `$CWD` for the directory the CLI
// ran in and `$REPO` for this repository.
//
// Every run gets exactly PATH, HOME, git's global and system configuration off,
// and the step's own extra variables — nothing else from this shell, so no CI
// variable of the machine that generates the corpus leaks in. git commits use a
// fixed author, committer and date.
//
// What stays genuinely nondeterministic, and is masked by the Swift test on
// both sides (never here): the `event_id` and wall-clock `created_at` of
// binding-registry events (bind, unbind and rebind take no clock or id flag),
// the random `event_id` of a proof event and so its signature and the next
// entry's `previous_entry_hash`, any timestamp of a run given no
// `--generated-at`, and keygen's fresh PEMs.
//
// THIS SCRIPT WRITES MARKERS FOR A LIVING. No line of this file, and no line of
// the file it generates, may begin with a marker: marker text is built at
// runtime below, and the corpus is emitted as ONE line of escaped JSON.
import { spawnSync } from "node:child_process";
import { createPrivateKey, createPublicKey } from "node:crypto";
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
  ["cli", "commands/markers"],
  ["cli", "commands/recover"],
  ["cli", "commands/keygen"],
  ["cli", "trustRender"],
  ["cli", "render"],
  ["cli", "runtime"],
  ["cli", "command/dispatch"],
  ["core", "markers/cli/bind"],
  ["core", "markers/cli/unbind"],
  ["core", "markers/cli/rebind"],
  ["core", "markers/cli/bindingLifecycle"],
  ["core", "markers/cli/scan"],
  ["core", "markers/cli/impact"],
  ["core", "markers/cli/prove"],
  ["core", "markers/cli/verify"],
  ["core", "markers/cli/validateLedger"],
  ["core", "markers/cli/shared"],
  ["core", "markers/cli/io"],
  ["core", "markers/keygen"],
  ["core", "markers/keyring"],
  ["core", "markers/ciAuthority"],
  ["core", "markers/appendOnly"],
  ["core", "markers/gitDiff"]
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

// A marker line, built at runtime so this file never carries one literally.
const token = (prefix) => `${prefix}: @use-` + "case:";
const startMarker = (prefix, slug) => `${token(prefix)}${slug}`;
const endMarker = (prefix, slug) => `${token(prefix)}end ${slug}`;

const seed = Buffer.alloc(32, 9);
const signingKey = createPrivateKey({
  key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]),
  format: "der",
  type: "pkcs8"
});
const PRIVATE_KEY_PEM = signingKey.export({ type: "pkcs8", format: "pem" }).toString();
const PUBLIC_KEY_PEM = createPublicKey(signingKey).export({ type: "spki", format: "pem" }).toString();
const otherKey = createPrivateKey({
  key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), Buffer.alloc(32, 7)]),
  format: "der",
  type: "pkcs8"
});
const OTHER_PUBLIC_KEY_PEM = createPublicKey(otherKey).export({ type: "spki", format: "pem" }).toString();

const RUN_KEY = "0123456789abcdef".repeat(4);
const GEN = "2026-09-17T12:00:00.000Z";
const LATER = "2026-09-18T12:00:00.000Z";

const GIT_ISOLATION = { GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
const GIT_IDENTITY = {
  GIT_AUTHOR_NAME: "Probe",
  GIT_AUTHOR_EMAIL: "probe@example.invalid",
  GIT_AUTHOR_DATE: "2026-01-01T00:00:00Z",
  GIT_COMMITTER_NAME: "Probe",
  GIT_COMMITTER_EMAIL: "probe@example.invalid",
  GIT_COMMITTER_DATE: "2026-01-01T00:00:00Z"
};

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

// A row whose verifier is `/bin/sh -c <script>` over `src/<name>.ts`; with
// `verifier: false` it requires a verifier nobody declared, so it blocks.
function row(name, { script = "exit 0", verifier = true, required = false, input = `src/${name}.ts` } = {}) {
  const policy = verifier
    ? `    verification_policy:
      mode: requirements
      verifiers:
        script:
          kind: script
          evidence_kind: test_result
          command: ["/bin/sh", "-c", ${JSON.stringify(script)}]
          inputs: [${JSON.stringify(input)}]
      requirements:
        - evidence_kind: test_result
          required_verifiers: [script]
          minimum_count: 1
`
    : `    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: test_result
          required_verifiers: [undeclared]
          minimum_count: 1
`;
  return `  - id: probe.core.${name}
    title: Row ${name}
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Probe ${name}.
    preconditions: [A source file exists.]
    trigger: An agent verifies.
    scenarios:
      - id: probe.core.${name}.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [It passes.]
    observable_outcomes: [The row reaches VERIFIED_LOCAL.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
${policy}    approval_policy:
      mode: none${required ? "\n      required_for_release: true" : ""}
`;
}

function matrix(rows) {
  return `schema_version: 1\nfeature:\n  id: probe.core\n  name: Probe\n  summary: Probe.\nuse_cases:\n${rows.join("")}`;
}

const source = (name) =>
  `export function ${name}One() {\n  return 1;\n}\n\nexport function ${name}Two() {\n  return 2;\n}\n\nexport function ${name}Three() {\n  return 3;\n}\n`;

const SWIFT_SOURCE = "import Foundation\n\nstruct Thing {\n  func run() -> Int {\n    return 1\n  }\n}\n";

// The standard workspace: alpha and beta pass, gamma's verifier fails, delta
// cannot be verified, and epsilon is required for release.
function workspace({ rows = null, git = false, extra = {} } = {}) {
  const definitions = rows ?? [
    row("alpha"),
    row("beta"),
    row("gamma", { script: "echo broken; exit 1" }),
    row("delta", { verifier: false }),
    row("epsilon", { required: true })
  ];
  const files = {
    "demo-repo/use-cases.yml": CONFIG,
    "demo-repo/use-cases/probe.yml": matrix(definitions),
    "demo-repo/src/alpha.ts": source("alpha"),
    "demo-repo/src/beta.ts": source("beta"),
    "demo-repo/src/gamma.ts": source("gamma"),
    "demo-repo/src/delta.ts": source("delta"),
    "demo-repo/src/epsilon.ts": source("epsilon"),
    "demo-repo/src/Thing.swift": SWIFT_SOURCE,
    "home/.use-cases/run-key": `${RUN_KEY}\n`,
    "outside/ci.pem": PRIVATE_KEY_PEM,
    "outside/ci.pub.pem": PUBLIC_KEY_PEM,
    "outside/other.pub.pem": OTHER_PUBLIC_KEY_PEM,
    ...extra
  };
  return { files, git };
}

const S = "$SANDBOX";
const R = "$ROOT";

// Steps.
const uc = (args, env = {}) => ({ kind: "uc", args, env });
const write = (path, content) => ({ kind: "write", path, content });
const edit = (path, from, to) => ({ kind: "edit", path, from, to });
const remove = (path) => ({ kind: "remove", path });
const git = (args) => ({ kind: "git", args });

const repo = ["--repo", S];
const gen = ["--generated-at", GEN];
const bind = (name, start = 1, end = 3, extra = []) =>
  uc(["bind", ...repo, "--row", `probe.core.${name}`, "--file", `src/${name}.ts`, "--mode", "explicit", "--start-line", String(start), "--end-line", String(end), "--json", ...extra]);
const verify = (target, extra = []) =>
  uc(["verify", ...repo, ...(target === "--all" ? ["--all"] : ["--row", `probe.core.${target}`]), ...gen, "--json", ...extra]);
const commitAll = [git(["add", "-A"]), git(["commit", "-q", "-m", "snapshot"])];
const signEnv = { UC_SIGNING_KEY: PRIVATE_KEY_PEM };
const trustedProve = (name) =>
  uc(["prove", ...repo, "--row", `probe.core.${name}`, "--verification-results", `${S}/.use-cases/verification-results.jsonl`, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", ...gen, "--json"], signEnv);

const ALPHA = `${S}/src/alpha.ts`;
const alphaMarkerLines = (slug = "probe.core.alpha") =>
  `${startMarker("//", slug)}\nexport function alphaOne() {\n  return 1;\n}\n${endMarker("//", slug)}\n`;

const keyring = (status, validUntil = null) =>
  JSON.stringify({
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys: [
      { key_id: "trusted-ci", algorithm: "ed25519", public_key: PUBLIC_KEY_PEM, valid_from: "2020-01-01T00:00:00Z", valid_until: validUntil, status }
    ]
  });
const KEYRING = keyring("active");
const REVOKED_KEYRING = keyring("revoked");
const EXPIRED_KEYRING = keyring("active", "2021-01-01T00:00:00Z");

// ---------------------------------------------------------------------------
// Cases: [name, setup, steps]

const bindCases = [
  ["bind_explicit_json", workspace(), [bind("alpha")]],
  ["bind_explicit_text", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3"])]],
  ["bind_swift_func_json", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/Thing.swift", "--mode", "swift-func", "--line", "4", "--json"])]],
  ["bind_swift_func_without_line", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/Thing.swift", "--mode", "swift-func", "--json"])]],
  ["bind_swift_func_not_a_function", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/Thing.swift", "--mode", "swift-func", "--line", "1", "--json"])]],
  ["bind_dry_run_json", workspace(), [bind("alpha", 1, 3, ["--dry-run"])]],
  ["bind_dry_run_text", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "5", "--end-line", "7", "--dry-run"])]],
  ["bind_two_suffixed_bindings", workspace(), [bind("alpha", 1, 3, ["--suffix", "one"]), bind("alpha", 7, 9, ["--suffix", "two"])]],
  ["bind_register_existing_implies_explicit", workspace({ extra: { "demo-repo/src/alpha.ts": alphaMarkerLines() } }), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--register-existing", "--json"])]],
  ["bind_register_existing_without_marker", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--register-existing", "--json"])]],
  ["bind_missing_row_json", workspace(), [uc(["bind", ...repo, "--file", "src/alpha.ts", "--mode", "explicit", "--json"])]],
  ["bind_missing_row_text", workspace(), [uc(["bind", ...repo, "--file", "src/alpha.ts", "--mode", "explicit"])]],
  ["bind_unknown_mode", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "inline", "--json"])]],
  ["bind_empty_row", workspace(), [uc(["bind", ...repo, "--row", "", "--file", "src/alpha.ts", "--mode", "explicit", "--json"])]],
  ["bind_unknown_row_json", workspace(), [uc(["bind", ...repo, "--row", "probe.core.nope", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--json"])]],
  ["bind_unknown_row_text", workspace(), [uc(["bind", ...repo, "--row", "probe.core.nope", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3"])]],
  ["bind_invalid_slug", workspace(), [uc(["bind", ...repo, "--row", "Probe Core", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--json"])]],
  ["bind_missing_source_file", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/missing.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--json"])]],
  ["bind_span_out_of_range", workspace(), [bind("alpha", 900, 902)]],
  ["bind_span_without_lines", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--json"])]],
  ["bind_non_numeric_line_is_absent", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "one", "--end-line", "3", "--json"])]],
  ["bind_duplicate_registration", workspace(), [bind("alpha"), bind("alpha", 5, 7)]],
  ["bind_no_comment_prefix", workspace({ extra: { "demo-repo/src/data.unknown": "a\nb\nc\n" } }), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/data.unknown", "--mode", "explicit", "--start-line", "1", "--end-line", "2", "--json"])]],
  ["bind_comment_prefix_override", workspace({ extra: { "demo-repo/src/data.unknown": "a\nb\nc\n" } }), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/data.unknown", "--mode", "explicit", "--start-line", "1", "--end-line", "2", "--comment-prefix", "#", "--json"])]],
  ["bind_shebang_script", workspace({ extra: { "demo-repo/tools/run": "#!/bin/sh\necho one\necho two\n" } }), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "tools/run", "--mode", "explicit", "--start-line", "2", "--end-line", "3", "--json"])]],
  ["bind_invalid_registry", workspace({ extra: { "demo-repo/.use-cases/bindings.jsonl": "not json\n" } }), [bind("alpha")]],
  ["bind_custom_bindings_path", workspace(), [bind("alpha", 1, 3, ["--bindings", `${R}/outside/bindings.jsonl`])]],
  ["bind_product_root", workspace(), [uc(["bind", ...repo, "--product-root", `${S}/src`, "--row", "probe.core.alpha", "--file", "alpha.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--json"])]],
  ["bind_absolute_file", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", ALPHA, "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--json"])]],
  ["bind_missing_repo_json", workspace(), [uc(["bind", "--repo", `${S}/missing`, "--row", "probe.core.alpha", "--json"])]],
  ["bind_missing_repo_text", workspace(), [uc(["bind", "--repo", `${S}/missing`, "--row", "probe.core.alpha"])]],
  ["bind_data_root_escape", workspace(), [uc(["bind", ...repo, "--data-root", `${R}/outside`, "--row", "probe.core.alpha", "--json"])]],
  ["bind_unparseable_matrix", workspace({ extra: { "demo-repo/use-cases/broken.yml": "a: [unclosed\n" } }), [bind("alpha")]],
  ["bind_unknown_flag", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--lines", "3", "--json"])]]
];

const unbindCases = [
  ["unbind_json", workspace(), [bind("alpha"), uc(["unbind", ...repo, "--row", "probe.core.alpha", "--json"])]],
  ["unbind_text", workspace(), [bind("alpha"), uc(["unbind", ...repo, "--row", "probe.core.alpha", "--reason", "row_retired"])]],
  ["unbind_dry_run", workspace(), [bind("alpha"), uc(["unbind", ...repo, "--row", "probe.core.alpha", "--dry-run", "--json"])]],
  ["unbind_not_registered", workspace(), [bind("alpha"), uc(["unbind", ...repo, "--row", "probe.core.alpha", "--suffix", "nothing-here", "--json"])]],
  ["unbind_missing_row_json", workspace(), [uc(["unbind", ...repo, "--json"])]],
  ["unbind_missing_row_text", workspace(), [uc(["unbind", ...repo])]],
  ["unbind_marker_stripped_by_hand", workspace(), [bind("alpha"), write("demo-repo/src/alpha.ts", source("alpha")), uc(["unbind", ...repo, "--row", "probe.core.alpha", "--json"])]],
  ["unbind_one_suffix_of_two", workspace(), [bind("alpha", 1, 3, ["--suffix", "one"]), bind("alpha", 7, 9, ["--suffix", "two"]), uc(["unbind", ...repo, "--row", "probe.core.alpha", "--suffix", "one", "--json"])]],
  ["unbind_row_left_the_matrix", workspace(), [bind("alpha"), write("demo-repo/use-cases/probe.yml", matrix([row("beta")])), uc(["unbind", ...repo, "--row", "probe.core.alpha", "--json"])]],
  ["unbind_invalid_slug", workspace(), [uc(["unbind", ...repo, "--row", "Probe Core", "--json"])]],
  ["unbind_missing_repo", workspace(), [uc(["unbind", "--repo", `${S}/missing`, "--row", "probe.core.alpha", "--json"])]]
];

const rebindCases = [
  ["rebind_same_file_json", workspace(), [bind("alpha"), uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "5", "--end-line", "7", "--json"])]],
  ["rebind_same_file_text", workspace(), [bind("alpha"), uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "5", "--end-line", "7", "--reason", "wrong_declaration"])]],
  ["rebind_across_files", workspace(), [bind("alpha"), uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/beta.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--json"])]],
  ["rebind_to_swift_func", workspace(), [bind("alpha"), uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/Thing.swift", "--mode", "swift-func", "--line", "4", "--json"])]],
  ["rebind_not_registered", workspace(), [uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--json"])]],
  ["rebind_span_out_of_range", workspace(), [bind("alpha"), uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "900", "--end-line", "902", "--json"])]],
  ["rebind_missing_mode_json", workspace(), [uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--json"])]],
  ["rebind_register_existing_does_not_imply_mode", workspace(), [uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--register-existing", "--json"])]],
  ["rebind_missing_mode_text", workspace(), [uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts"])]],
  ["rebind_dry_run", workspace(), [bind("alpha"), uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/beta.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--dry-run", "--json"])]],
  ["rebind_marker_already_gone", workspace(), [bind("alpha"), write("demo-repo/src/alpha.ts", source("alpha")), uc(["rebind", ...repo, "--row", "probe.core.alpha", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "5", "--end-line", "7", "--json"])]],
  ["rebind_suffixed_moves_alone", workspace(), [bind("alpha", 1, 3, ["--suffix", "one"]), bind("alpha", 7, 9, ["--suffix", "two"]), uc(["rebind", ...repo, "--row", "probe.core.alpha", "--suffix", "two", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "9", "--end-line", "11", "--json"])]]
];

const scanCases = [
  ["scan_unbound_json", workspace(), [uc(["scan", ...repo, ...gen, "--json"])]],
  ["scan_unbound_text", workspace(), [uc(["scan", ...repo, ...gen])]],
  ["scan_single_unbound_row_text", workspace({ rows: [row("alpha")] }), [uc(["scan", ...repo, ...gen])]],
  ["scan_empty_matrix_text", workspace({ rows: [] }), [uc(["scan", ...repo, ...gen])]],
  ["scan_verified_local_text", workspace(), [bind("alpha"), verify("alpha"), uc(["scan", ...repo, ...gen])]],
  ["scan_verified_local_json", workspace(), [bind("alpha"), verify("alpha"), uc(["scan", ...repo, ...gen, "--json"])]],
  ["scan_stale_local_text", workspace(), [bind("alpha"), verify("alpha"), edit("demo-repo/src/alpha.ts", "return 1;", "return 11;"), uc(["scan", ...repo, ...gen])]],
  ["scan_mixed_text", workspace(), [bind("alpha"), bind("beta"), bind("gamma"), bind("delta"), verify("--all"), uc(["scan", ...repo, ...gen])]],
  ["scan_mixed_json", workspace(), [bind("alpha"), bind("beta"), bind("gamma"), verify("--all"), uc(["scan", ...repo, ...gen, "--json"])]],
  ["scan_gate_blocked_text", workspace(), [bind("alpha"), verify("alpha"), uc(["scan", ...repo, ...gen, "--gate"])]],
  ["scan_gate_blocked_json", workspace(), [uc(["scan", ...repo, ...gen, "--gate", "--json"])]],
  ["scan_gate_passes_with_ungated_drift_text", workspace(), [bind("epsilon"), verify("epsilon"), uc(["scan", ...repo, ...gen, "--gate"])]],
  ["scan_gate_single_required_text", workspace({ rows: [row("epsilon", { required: true })] }), [bind("epsilon"), verify("epsilon"), uc(["scan", ...repo, ...gen, "--gate"])]],
  ["scan_gate_release_mode_text", workspace(), [bind("epsilon"), verify("epsilon"), uc(["scan", ...repo, ...gen, "--gate", "--policy-mode", "release"])]],
  ["scan_gate_custom_mode_json", workspace(), [bind("epsilon"), verify("epsilon"), uc(["scan", ...repo, ...gen, "--gate", "--policy-mode", "custom", "--json"])]],
  ["scan_unknown_policy_mode_is_feature", workspace(), [uc(["scan", ...repo, ...gen, "--policy-mode", "strict", "--json"])]],
  ["scan_missing_marker_integrity_text", workspace(), [bind("alpha"), write("demo-repo/src/alpha.ts", source("alpha")), uc(["scan", ...repo, ...gen])]],
  ["scan_missing_marker_integrity_json", workspace(), [bind("alpha"), write("demo-repo/src/alpha.ts", source("alpha")), uc(["scan", ...repo, ...gen, "--json"])]],
  ["scan_registry_row_missing_text", workspace(), [bind("alpha"), write("demo-repo/use-cases/probe.yml", matrix([row("beta")])), uc(["scan", ...repo, ...gen])]],
  ["scan_unregistered_marker_text", workspace({ extra: { "demo-repo/src/alpha.ts": alphaMarkerLines() } }), [uc(["scan", ...repo, ...gen])]],
  ["scan_corrupt_registry_text", workspace({ extra: { "demo-repo/.use-cases/bindings.jsonl": "{\"schema\":\"nope\"}\n" } }), [uc(["scan", ...repo, ...gen])]],
  ["scan_ci_prints_inferred_swift_spans", workspace(), [uc(["bind", ...repo, "--row", "probe.core.alpha", "--file", "src/Thing.swift", "--mode", "swift-func", "--line", "4", "--json"]), uc(["scan", ...repo, ...gen, "--ci", "--json"])]],
  ["scan_ci_without_swift_spans", workspace(), [bind("alpha"), uc(["scan", ...repo, ...gen, "--ci", "--json"])]],
  ["scan_results_override", workspace(), [bind("alpha"), uc(["verify", ...repo, "--row", "probe.core.alpha", ...gen, "--out", `${R}/outside/results.jsonl`, "--json"]), uc(["scan", ...repo, ...gen, "--results", `${R}/outside/results.jsonl`])]],
  ["scan_results_default_ignores_other_file", workspace(), [bind("alpha"), uc(["verify", ...repo, "--row", "probe.core.alpha", ...gen, "--out", `${R}/outside/results.jsonl`, "--json"]), uc(["scan", ...repo, ...gen])]],
  ["scan_other_run_key_reads_unattested", workspace(), [bind("alpha"), verify("alpha"), write("home/.use-cases/run-key", `${"f".repeat(64)}\n`), uc(["scan", ...repo, ...gen, "--json"])]],
  ["scan_run_key_file_variable", workspace(), [bind("alpha"), uc(["verify", ...repo, "--row", "probe.core.alpha", ...gen, "--json"], { UC_RUN_KEY_FILE: `${R}/outside/run-key` }), uc(["scan", ...repo, ...gen], { UC_RUN_KEY_FILE: `${R}/outside/run-key` }), uc(["scan", ...repo, ...gen])]],
  ["scan_signed_proof_fresh_text", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["scan", ...repo, ...gen, "--public-key", `${R}/outside/ci.pub.pem`])]],
  ["scan_signed_proof_fresh_json", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["scan", ...repo, ...gen, "--public-key", `${R}/outside/ci.pub.pem`, "--json"])]],
  ["scan_signed_proof_keyless_text", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["scan", ...repo, ...gen])]],
  ["scan_signed_proof_wrong_key_text", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["scan", ...repo, ...gen, "--public-key", `${R}/outside/other.pub.pem`])]],
  ["scan_private_key_as_public_key", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["scan", ...repo, ...gen, "--public-key", `${R}/outside/ci.pem`, "--json"])]],
  ["scan_keyring_text", workspace({ extra: { "outside/keyring.json": KEYRING } }), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["scan", ...repo, ...gen, "--keyring", `${R}/outside/keyring.json`, "--public-key", `${R}/outside/other.pub.pem`])]],
  ["scan_revoked_keyring_text", workspace({ extra: { "outside/keyring.json": REVOKED_KEYRING } }), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["scan", ...repo, ...gen, "--keyring", `${R}/outside/keyring.json`])]],
  ["scan_expired_keyring_json", workspace({ extra: { "outside/keyring.json": EXPIRED_KEYRING } }), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["scan", ...repo, ...gen, "--keyring", `${R}/outside/keyring.json`, "--json"])]],
  ["scan_keyring_invalid_json", workspace({ extra: { "outside/keyring.json": "{not json" } }), [uc(["scan", ...repo, ...gen, "--keyring", `${R}/outside/keyring.json`, "--json"])]],
  ["scan_keyring_schema_invalid_text", workspace({ extra: { "outside/keyring.json": "{\"schema_version\":1}" } }), [uc(["scan", ...repo, ...gen, "--keyring", `${R}/outside/keyring.json`])]],
  ["scan_keyring_missing", workspace(), [uc(["scan", ...repo, ...gen, "--keyring", `${R}/outside/missing.json`, "--json"])]],
  ["scan_public_key_missing_json", workspace(), [uc(["scan", ...repo, ...gen, "--public-key", `${R}/outside/missing.pem`, "--json"])]],
  ["scan_public_key_missing_relative_text", workspace(), [uc(["scan", ...repo, ...gen, "--public-key", "missing.pem"])]],
  ["scan_public_key_garbage_json", workspace({ extra: { "outside/garbage.pem": "garbage\n" } }), [uc(["scan", ...repo, ...gen, "--public-key", `${R}/outside/garbage.pem`, "--json"])]],
  ["scan_public_key_garbage_text", workspace({ extra: { "outside/garbage.pem": "garbage\n" } }), [uc(["scan", ...repo, ...gen, "--public-key", `${R}/outside/garbage.pem`])]],
  ["scan_public_key_empty_flag_is_keyless", workspace(), [uc(["scan", ...repo, ...gen, "--public-key", "", "--json"])]],
  ["scan_tampered_proof_ledger_text", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), edit("demo-repo/.use-cases/proofs.jsonl", "\"result\":\"pass\"", "\"result\":\"fail\""), uc(["scan", ...repo, ...gen, "--public-key", `${R}/outside/ci.pub.pem`])]],
  ["scan_custom_proofs_and_bindings", workspace(), [bind("alpha", 1, 3, ["--bindings", `${R}/outside/bindings.jsonl`]), uc(["scan", ...repo, ...gen, "--bindings", `${R}/outside/bindings.jsonl`, "--proofs", `${R}/outside/proofs.jsonl`, "--json"])]],
  ["scan_product_root", workspace(), [bind("alpha"), uc(["scan", ...repo, ...gen, "--product-root", `${S}/src`, "--json"])]],
  ["scan_without_generated_at", workspace(), [uc(["scan", ...repo, "--json"])]],
  ["scan_base_ref_in_git", workspace({ git: true }), [bind("alpha"), ...commitAll, uc(["scan", ...repo, ...gen, "--base-ref", "HEAD", "--json"])]],
  ["scan_base_ref_outside_git", workspace(), [uc(["scan", ...repo, ...gen, "--base-ref", "HEAD", "--json"])]],
  ["scan_nested_workspace_not_walked", workspace({ extra: { "demo-repo/nested/use-cases.yml": CONFIG, "demo-repo/nested/src/x.ts": `${startMarker("//", "probe.core.zeta")}\nx\n${endMarker("//", "probe.core.zeta")}\n` } }), [uc(["scan", ...repo, ...gen])]],
  ["scan_missing_repo_text", workspace(), [uc(["scan", "--repo", `${S}/missing`, ...gen])]],
  ["scan_missing_repo_json", workspace(), [uc(["scan", "--repo", `${S}/missing`, ...gen, "--json"])]],
  ["scan_unparseable_matrix_text", workspace({ extra: { "demo-repo/use-cases/broken.yml": "a: [unclosed\n" } }), [uc(["scan", ...repo, ...gen])]],
  ["scan_unknown_flag_text", workspace(), [uc(["scan", ...repo, "--gates"])]]
];

const IMPACT_GIT = workspace({ git: true });
const impactSetup = [bind("alpha"), bind("beta"), bind("gamma"), ...commitAll];
const impactCases = [
  ["impact_not_a_git_repository_json", workspace(), [bind("alpha"), uc(["impact", ...repo, ...gen, "--json"])]],
  ["impact_not_a_git_repository_text", workspace(), [uc(["impact", ...repo, ...gen])]],
  ["impact_no_changes_text", IMPACT_GIT, [...impactSetup, uc(["impact", ...repo, ...gen])]],
  ["impact_no_changes_json", IMPACT_GIT, [...impactSetup, uc(["impact", ...repo, ...gen, "--json"])]],
  ["impact_span_hit_text", IMPACT_GIT, [...impactSetup, edit("demo-repo/src/alpha.ts", "return 1;", "return 11;"), uc(["impact", ...repo, ...gen])]],
  ["impact_single_span_hit_text", IMPACT_GIT, [bind("alpha"), ...commitAll, edit("demo-repo/src/alpha.ts", "return 1;", "return 11;"), uc(["impact", ...repo, ...gen])]],
  ["impact_span_hit_and_touched_json", IMPACT_GIT, [...impactSetup, edit("demo-repo/src/alpha.ts", "return 1;", "return 11;"), edit("demo-repo/src/beta.ts", "return 3;", "return 33;"), uc(["impact", ...repo, ...gen, "--json"])]],
  ["impact_touched_text", IMPACT_GIT, [...impactSetup, edit("demo-repo/src/beta.ts", "return 3;", "return 33;"), edit("demo-repo/src/gamma.ts", "return 3;", "return 33;"), uc(["impact", ...repo, ...gen])]],
  ["impact_single_touched_text", IMPACT_GIT, [...impactSetup, edit("demo-repo/src/beta.ts", "return 3;", "return 33;"), uc(["impact", ...repo, ...gen])]],
  ["impact_deleted_file_text", IMPACT_GIT, [...impactSetup, remove("demo-repo/src/alpha.ts"), uc(["impact", ...repo, ...gen])]],
  ["impact_deleted_files_json", IMPACT_GIT, [...impactSetup, remove("demo-repo/src/alpha.ts"), remove("demo-repo/src/beta.ts"), git(["add", "-A"]), uc(["impact", ...repo, ...gen, "--staged", "--json"])]],
  ["impact_renamed_file_text", IMPACT_GIT, [...impactSetup, git(["mv", "src/alpha.ts", "src/renamed.ts"]), uc(["impact", ...repo, ...gen, "--staged"])]],
  ["impact_staged_only", IMPACT_GIT, [...impactSetup, edit("demo-repo/src/alpha.ts", "return 1;", "return 11;"), git(["add", "src/alpha.ts"]), edit("demo-repo/src/beta.ts", "return 2;", "return 22;"), uc(["impact", ...repo, ...gen, "--staged", "--json"])]],
  ["impact_base_ref_text", IMPACT_GIT, [...impactSetup, edit("demo-repo/src/alpha.ts", "return 1;", "return 11;"), ...commitAll, uc(["impact", ...repo, ...gen, "--base", "HEAD~1"])]],
  ["impact_unknown_base_ref_json", IMPACT_GIT, [...impactSetup, uc(["impact", ...repo, ...gen, "--base", "no-such-ref", "--json"])]],
  ["impact_unknown_base_ref_text", IMPACT_GIT, [...impactSetup, uc(["impact", ...repo, ...gen, "--base", "no-such-ref"])]],
  ["impact_git_repository_without_commits", IMPACT_GIT, [bind("alpha"), uc(["impact", ...repo, ...gen, "--json"])]],
  ["impact_public_key_garbage", workspace({ extra: { "outside/garbage.pem": "garbage\n" } }), [uc(["impact", ...repo, ...gen, "--public-key", `${R}/outside/garbage.pem`, "--json"])]],
  ["impact_missing_repo_text", workspace(), [uc(["impact", "--repo", `${S}/missing`])]]
];

const verifyCases = [
  ["verify_row_pass_json", workspace(), [bind("alpha"), verify("alpha")]],
  ["verify_row_pass_text", workspace(), [bind("alpha"), uc(["verify", ...repo, "--row", "probe.core.alpha", ...gen])]],
  ["verify_all_mixed_text", workspace(), [bind("alpha"), bind("beta"), bind("gamma"), bind("delta"), uc(["verify", ...repo, "--all", ...gen])]],
  ["verify_all_mixed_json", workspace(), [bind("alpha"), bind("gamma"), bind("delta"), verify("--all")]],
  ["verify_row_fail_text", workspace(), [bind("gamma"), uc(["verify", ...repo, "--row", "probe.core.gamma", ...gen])]],
  ["verify_dry_run_text", workspace(), [bind("alpha"), bind("delta"), uc(["verify", ...repo, "--all", "--dry-run", ...gen])]],
  ["verify_dry_run_single_text", workspace(), [bind("alpha"), uc(["verify", ...repo, "--row", "probe.core.alpha", "--dry-run", ...gen])]],
  ["verify_dry_run_json", workspace(), [bind("alpha"), bind("delta"), verify("--all", ["--dry-run"])]],
  ["verify_dry_run_nothing_bound_text", workspace(), [uc(["verify", ...repo, "--all", "--dry-run", ...gen])]],
  ["verify_dry_run_invalid_binding_text", workspace(), [bind("alpha"), write("demo-repo/src/alpha.ts", `${alphaMarkerLines()}${alphaMarkerLines()}`), uc(["verify", ...repo, "--all", "--dry-run", ...gen])]],
  ["verify_nothing_bound_text", workspace(), [uc(["verify", ...repo, "--all", ...gen])]],
  ["verify_missing_target_json", workspace(), [uc(["verify", ...repo, "--json"])]],
  ["verify_missing_target_text", workspace(), [uc(["verify", ...repo])]],
  ["verify_empty_row_is_no_target", workspace(), [uc(["verify", ...repo, "--row", "", "--json"])]],
  ["verify_unknown_row_json", workspace(), [uc(["verify", ...repo, "--row", "probe.core.nope", ...gen, "--json"])]],
  ["verify_unknown_row_text", workspace(), [uc(["verify", ...repo, "--row", "probe.core.nope", ...gen])]],
  ["verify_unbound_row", workspace(), [verify("alpha")]],
  ["verify_out_path", workspace(), [bind("alpha"), verify("alpha", ["--out", `${R}/outside/results.jsonl`])]],
  ["verify_preserves_other_rows", workspace(), [bind("alpha"), bind("beta"), verify("alpha"), verify("beta"), verify("alpha")]],
  ["verify_ledger_invalid_text", workspace({ extra: { "demo-repo/.use-cases/bindings.jsonl": "{\"schema\":\"nope\"}\n" } }), [uc(["verify", ...repo, "--all", ...gen])]],
  ["verify_ledger_invalid_json", workspace({ extra: { "demo-repo/.use-cases/bindings.jsonl": "{\"schema\":\"nope\"}\n" } }), [verify("--all")]],
  ["verify_signed_proof_keyless_is_not_blocked", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), verify("alpha")]],
  ["verify_signed_proof_wrong_key_blocks", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["verify", ...repo, "--row", "probe.core.alpha", ...gen, "--public-key", `${R}/outside/other.pub.pem`])]],
  ["verify_mints_a_run_key", workspace({ extra: { "home/.use-cases/run-key": "" } }), [bind("alpha"), verify("alpha")]],
  ["verify_without_generated_at", workspace(), [bind("alpha"), uc(["verify", ...repo, "--row", "probe.core.alpha", "--json"])]],
  ["verify_missing_repo_text", workspace(), [uc(["verify", "--repo", `${S}/missing`, "--all"])]]
];

const proveResults = ["--verification-results", `${S}/.use-cases/verification-results.jsonl`];
const proveCases = [
  ["prove_missing_target_json", workspace(), [uc(["prove", ...repo, "--json"])]],
  ["prove_missing_target_text", workspace(), [uc(["prove", ...repo])]],
  ["prove_untrusted_append", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--append", ...gen, "--json"])]],
  ["prove_candidate_json", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, ...gen, "--json"])]],
  ["prove_candidate_text", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, ...gen])]],
  ["prove_without_results_json", workspace(), [bind("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...gen, "--json"])]],
  ["prove_trusted_signed_json", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha")]],
  ["prove_trusted_signed_text", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--key-id", "ci-key-1", "--append", ...gen], signEnv)]],
  ["prove_trusted_all_with_failures", workspace(), [bind("alpha"), bind("gamma"), verify("--all"), uc(["prove", ...repo, "--all", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", ...gen, "--json"], signEnv)]],
  ["prove_twice_chains_entries", workspace(), [bind("alpha"), bind("beta"), verify("--all"), trustedProve("alpha"), trustedProve("beta"), uc(["validate-ledger", ...repo, "--public-key", `${R}/outside/ci.pub.pem`, "--json"])]],
  ["prove_refresh_after_fresh", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", "--refresh", "--public-key", `${R}/outside/ci.pub.pem`, ...gen, "--json"], signEnv)]],
  ["prove_signing_key_env_unset", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", ...gen, "--json"])]],
  ["prove_signing_key_garbage_json", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", ...gen, "--json"], { UC_SIGNING_KEY: "garbage" })]],
  ["prove_signing_key_garbage_text", workspace(), [uc(["prove", ...repo, "--row", "probe.core.alpha", "--signing-key-env", "UC_SIGNING_KEY", ...gen], { UC_SIGNING_KEY: "garbage" })]],
  ["prove_signing_key_is_public", workspace(), [uc(["prove", ...repo, "--row", "probe.core.alpha", "--signing-key-env", "UC_SIGNING_KEY", ...gen, "--json"], { UC_SIGNING_KEY: PUBLIC_KEY_PEM })]],
  ["prove_trusted_dry_run", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--dry-run", ...gen, "--json"])]],
  ["prove_results_unreadable_json", workspace(), [uc(["prove", ...repo, "--row", "probe.core.alpha", "--verification-results", `${R}/outside/missing.jsonl`, "--json"])]],
  ["prove_results_unreadable_text", workspace(), [uc(["prove", ...repo, "--all", "--verification-results", `${R}/outside/missing.jsonl`])]],
  ["prove_results_not_jsonl", workspace({ extra: { "outside/results.jsonl": "{\"ok\":1}\nnot json\n" } }), [uc(["prove", ...repo, "--row", "probe.core.alpha", "--verification-results", `${R}/outside/results.jsonl`, "--json"])]],
  ["prove_results_blank_lines_and_scalars", workspace({ extra: { "outside/results.jsonl": "\n  \n1\n\"text\"\n" } }), [bind("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", "--verification-results", `${R}/outside/results.jsonl`, ...gen, "--json"])]],
  ["prove_authority_file", workspace({ extra: { "outside/authority.json": "{\"type\":\"ci\",\"provider\":\"generic\",\"repository\":\"probe/repo\",\"protected_ref\":true}" } }), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", "--authority-file", `${R}/outside/authority.json`, ...gen, "--json"], signEnv)]],
  ["prove_authority_file_unreadable", workspace(), [uc(["prove", ...repo, "--row", "probe.core.alpha", "--authority-file", `${R}/outside/missing.json`, "--json"])]],
  ["prove_authority_file_invalid_json", workspace({ extra: { "outside/authority.json": "{nope" } }), [uc(["prove", ...repo, "--row", "probe.core.alpha", "--authority-file", `${R}/outside/authority.json`, "--json"])]],
  ["prove_authority_file_null", workspace({ extra: { "outside/authority.json": "null" } }), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", "--authority-file", `${R}/outside/authority.json`, ...gen, "--json"], signEnv)]],
  ["prove_github_actions_environment", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", ...gen, "--json"], { ...signEnv, GITHUB_ACTIONS: "true", GITHUB_REPOSITORY: "probe/repo", GITHUB_REF: "refs/heads/main", GITHUB_SHA: "abc123", GITHUB_RUN_ID: "42", GITHUB_ACTOR: "probe", GITHUB_EVENT_NAME: "push" })]],
  ["prove_gitlab_environment", workspace(), [bind("alpha"), verify("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", ...proveResults, "--trusted-ci", "--signing-key-env", "UC_SIGNING_KEY", "--append", ...gen, "--json"], { ...signEnv, GITLAB_CI: "true", CI_PROJECT_PATH: "probe/repo", CI_COMMIT_REF_PROTECTED: "true" })]],
  ["prove_unsafe_assume_ignored", workspace(), [bind("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", "--unsafe-assume-verification-result", "pass", ...gen, "--json"])]],
  ["prove_unsafe_assume_honoured", workspace(), [bind("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", "--unsafe-assume-verification-result", "pass", ...gen, "--json"], { UCM_ALLOW_UNSAFE_VERIFICATION: "1" })]],
  ["prove_unsafe_assume_other_value", workspace(), [bind("alpha"), uc(["prove", ...repo, "--row", "probe.core.alpha", "--unsafe-assume-verification-result", "fail", ...gen, "--json"], { UCM_ALLOW_UNSAFE_VERIFICATION: "1" })]],
  ["prove_unknown_row", workspace(), [uc(["prove", ...repo, "--row", "probe.core.nope", ...gen, "--json"])]],
  ["prove_ledger_invalid", workspace({ extra: { "demo-repo/.use-cases/bindings.jsonl": "not json\n" } }), [uc(["prove", ...repo, "--all", ...gen, "--json"])]],
  ["prove_missing_repo", workspace(), [uc(["prove", "--repo", `${S}/missing`, "--all", "--json"])]]
];

const validateCases = [
  ["validate_ledger_empty_json", workspace(), [uc(["validate-ledger", ...repo, "--json"])]],
  ["validate_ledger_empty_text", workspace(), [uc(["validate-ledger", ...repo])]],
  ["validate_ledger_bindings_json", workspace(), [bind("alpha"), bind("beta"), uc(["unbind", ...repo, "--row", "probe.core.beta", "--json"]), uc(["validate-ledger", ...repo, "--json"])]],
  ["validate_ledger_proof_without_key_text", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["validate-ledger", ...repo])]],
  ["validate_ledger_proof_with_key_text", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["validate-ledger", ...repo, "--public-key", `${R}/outside/ci.pub.pem`])]],
  ["validate_ledger_proof_with_keyring_json", workspace({ extra: { "outside/keyring.json": KEYRING } }), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["validate-ledger", ...repo, "--keyring", `${R}/outside/keyring.json`, "--json"])]],
  ["validate_ledger_tampered_proof_json", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), edit("demo-repo/.use-cases/proofs.jsonl", "\"result\":\"pass\"", "\"result\":\"fail\""), uc(["validate-ledger", ...repo, "--public-key", `${R}/outside/ci.pub.pem`, "--json"])]],
  ["validate_ledger_corrupt_registry_json", workspace({ extra: { "demo-repo/.use-cases/bindings.jsonl": "not json\n{\"schema\":\"nope\"}\n" } }), [uc(["validate-ledger", ...repo, "--json"])]],
  ["validate_ledger_corrupt_registry_text", workspace({ extra: { "demo-repo/.use-cases/bindings.jsonl": "not json\n" } }), [uc(["validate-ledger", ...repo])]],
  ["validate_ledger_row_left_matrix", workspace(), [bind("alpha"), write("demo-repo/use-cases/probe.yml", matrix([row("beta")])), uc(["validate-ledger", ...repo, "--json"])]],
  ["validate_ledger_base_ref_misses_rewrite", workspace({ git: true }), [bind("alpha"), ...commitAll, edit("demo-repo/.use-cases/bindings.jsonl", "\"reason\":\"initial_bind\"", "\"reason\":\"rewritten\""), uc(["validate-ledger", ...repo, "--base-ref", "HEAD", "--json"])]],
  ["validate_ledger_base_ref_unknown", workspace({ git: true }), [bind("alpha"), ...commitAll, uc(["validate-ledger", ...repo, "--base-ref", "no-such-ref", "--json"])]],
  ["validate_ledger_base_ref_outside_git", workspace(), [uc(["validate-ledger", ...repo, "--base-ref", "HEAD", "--json"])]],
  ["validate_ledger_custom_paths", workspace(), [bind("alpha", 1, 3, ["--bindings", `${R}/outside/bindings.jsonl`]), uc(["validate-ledger", ...repo, "--bindings", `${R}/outside/bindings.jsonl`, "--proofs", `${R}/outside/proofs.jsonl`, "--json"])]],
  ["validate_ledger_public_key_missing_text", workspace(), [uc(["validate-ledger", ...repo, "--public-key", `${R}/outside/missing.pem`])]],
  ["validate_ledger_missing_repo", workspace(), [uc(["validate-ledger", "--repo", `${S}/missing`, "--json"])]]
];

const recoverCases = [
  ["recover_missing_target_json", workspace(), [uc(["recover", ...repo, "--json"])]],
  ["recover_missing_target_text", workspace(), [uc(["recover", ...repo])]],
  ["recover_row_green_text", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", ...gen])]],
  ["recover_row_green_json", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", ...gen, "--json"])]],
  ["recover_all_green_text", workspace({ rows: [row("alpha"), row("beta")] }), [bind("alpha"), bind("beta"), uc(["recover", ...repo, "--all", ...gen])]],
  ["recover_all_with_unbound_rows_text", workspace(), [bind("alpha"), uc(["recover", ...repo, "--all", ...gen])]],
  ["recover_failing_verifier_text", workspace(), [bind("alpha"), bind("gamma"), uc(["recover", ...repo, "--all", ...gen])]],
  ["recover_failing_verifier_json", workspace(), [bind("gamma"), uc(["recover", ...repo, "--row", "probe.core.gamma", ...gen, "--json"])]],
  ["recover_blocked_verifier_text", workspace(), [bind("delta"), uc(["recover", ...repo, "--row", "probe.core.delta", ...gen])]],
  ["recover_unbound_row_text", workspace(), [uc(["recover", ...repo, "--row", "probe.core.alpha", ...gen])]],
  ["recover_unbound_row_json", workspace(), [uc(["recover", ...repo, "--row", "probe.core.alpha", ...gen, "--json"])]],
  ["recover_unknown_row_text", workspace(), [uc(["recover", ...repo, "--row", "probe.core.nope", ...gen])]],
  ["recover_nothing_bound_all_text", workspace(), [uc(["recover", ...repo, "--all", ...gen])]],
  ["recover_signing_key_env_empty_json", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", "--signing-key-env", "UC_SIGNING_KEY", ...gen, "--json"])]],
  ["recover_signing_key_env_empty_text", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", "--signing-key-env", "UC_SIGNING_KEY", ...gen], { UC_SIGNING_KEY: "" })]],
  ["recover_signing_key_garbage", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", "--signing-key-env", "UC_SIGNING_KEY", ...gen, "--json"], { UC_SIGNING_KEY: "garbage" })]],
  ["recover_signed_fresh_text", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", "--signing-key-env", "UC_SIGNING_KEY", "--public-key", `${R}/outside/ci.pub.pem`, ...gen], signEnv)]],
  ["recover_signed_fresh_json", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", "--signing-key-env", "UC_SIGNING_KEY", "--key-id", "ci-key-1", "--public-key", `${R}/outside/ci.pub.pem`, ...gen, "--json"], signEnv)]],
  ["recover_signed_without_public_key_text", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", "--signing-key-env", "UC_SIGNING_KEY", ...gen], signEnv)]],
  ["recover_signed_all_json", workspace(), [bind("alpha"), bind("beta"), uc(["recover", ...repo, "--all", "--signing-key-env", "UC_SIGNING_KEY", "--public-key", `${R}/outside/ci.pub.pem`, ...gen, "--json"], signEnv)]],
  ["recover_existing_signed_proof_keyless_text", workspace(), [bind("alpha"), verify("alpha"), trustedProve("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", ...gen])]],
  ["recover_integrity_error_text", workspace(), [bind("alpha"), bind("beta"), write("demo-repo/src/beta.ts", source("beta")), uc(["recover", ...repo, "--row", "probe.core.alpha", ...gen])]],
  ["recover_variant_family", workspace({
    rows: [`  - id: probe.core.family
    title: Row family
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Probe family.
    preconditions: [A source file exists.]
    trigger: An agent verifies.
    variants:
      - key: one
      - key: two
    scenarios:
      - id: probe.core.family.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [It passes.]
    observable_outcomes: [The row reaches VERIFIED_LOCAL.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        script:
          kind: script
          evidence_kind: test_result
          command: ["/bin/sh", "-c", "echo {variant}"]
          inputs: ["src/alpha.ts"]
      requirements:
        - evidence_kind: test_result
          required_verifiers: [script]
          minimum_count: 1
    approval_policy:
      mode: none
`]
  }), [uc(["bind", ...repo, "--row", "probe.core.family", "--file", "src/alpha.ts", "--mode", "explicit", "--start-line", "1", "--end-line", "3", "--json"]), uc(["recover", ...repo, "--all", ...gen, "--json"]), uc(["recover", ...repo, "--all", ...gen])]],
  ["recover_without_generated_at", workspace(), [bind("alpha"), uc(["recover", ...repo, "--row", "probe.core.alpha", "--json"])]],
  ["recover_missing_repo_text", workspace(), [uc(["recover", "--repo", `${S}/missing`, "--all"])]]
];

const keygenCases = [
  ["keygen_print_json", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--json"])]],
  ["keygen_print_text", { files: {}, git: false }, [uc(["keygen", "--repo", S])]],
  ["keygen_print_ci_github_json", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--ci", "github", "--json"])]],
  ["keygen_print_ci_github_text", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--ci", "github"])]],
  ["keygen_out_json", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--out", `${R}/outside/keys`, "--json"])]],
  ["keygen_out_text", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--out", `${R}/outside/nested/keys`])]],
  ["keygen_out_ci_github_json", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--out", `${R}/outside/keys`, "--ci", "github", "--json"])]],
  ["keygen_out_inside_repo_json", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--out", `${S}/keys`, "--json"])]],
  ["keygen_out_is_repo_text", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--out", S])]],
  ["keygen_out_sibling_with_repo_prefix", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--out", `${S}-keys`, "--json"])]],
  ["keygen_without_repo_uses_cwd", { files: {}, git: false }, [uc(["keygen", "--out", `${R}/outside/keys`, "--json"])]],
  ["keygen_unsupported_ci_json", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--ci", "gitlab", "--json"])]],
  ["keygen_unsupported_ci_text", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--ci", "", "--out", `${R}/outside/keys`])]],
  ["keygen_missing_repo_is_fine", { files: {}, git: false }, [uc(["keygen", "--repo", `${S}/missing`, "--json"])]],
  ["keygen_unknown_flag", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--output", "x", "--json"])]],
  ["keygen_ignores_workspace_flags", { files: {}, git: false }, [uc(["keygen", "--repo", S, "--data-root", `${R}/outside`, "--json"])]]
];

const cases = [
  ...bindCases,
  ...unbindCases,
  ...rebindCases,
  ...scanCases,
  ...impactCases,
  ...verifyCases,
  ...proveCases,
  ...validateCases,
  ...recoverCases,
  ...keygenCases
];

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

// keygen mints a fresh keypair on every run. Its PEMs are replaced before they
// are recorded, so no key it generated ever lands in this repository; the Swift
// test applies the same replacement to its own output.
const PEM_BLOCK = /-----BEGIN (PRIVATE|PUBLIC) KEY-----(\n|\\n)[A-Za-z0-9+/=]+(\n|\\n)-----END (PRIVATE|PUBLIC) KEY-----/g;
const withoutMintedKeys = (text) =>
  text.replace(PEM_BLOCK, (_match, kind, newline) => `-----BEGIN ${kind} KEY-----${newline}<minted>${newline}-----END ${kind} KEY-----`);

const names = new Set();
const recorded = [];
for (const [name, setup, steps] of cases) {
  if (names.has(name)) throw new Error(`duplicate case ${name}`);
  names.add(name);
  const root = realpathSync(mkdtempSync(join(tmpdir(), "uc-markers-")));
  const sandbox = join(root, "demo-repo");
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "uc-markers-cwd-")));
  const placeholders = (text) =>
    text.split(sandbox).join("$SANDBOX").split(root).join("$ROOT").split(cwd).join("$CWD").split(repositoryRoot).join("$REPO");
  const concrete = (text) =>
    text.split("$SANDBOX").join(sandbox).split("$ROOT").join(root).split("$CWD").join(cwd).split("$REPO").join(repositoryRoot);
  const baseEnvironment = { PATH: process.env.PATH, HOME: join(root, "home"), ...GIT_ISOLATION };
  const runGit = (args) => {
    const result = spawnSync("git", args, { cwd: sandbox, encoding: "utf8", env: { ...baseEnvironment, ...GIT_IDENTITY } });
    if (result.status !== 0) throw new Error(`${name}: git ${args.join(" ")} failed: ${result.stderr}`);
  };
  try {
    mkdirSync(join(root, "outside"));
    mkdirSync(join(root, "home"));
    mkdirSync(sandbox);
    if (setup.git) runGit(["init", "-q"]);
    for (const [path, content] of Object.entries(setup.files)) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), content);
    }
    const runs = [];
    const runsKeygen = steps.some((step) => step.kind === "uc" && step.args[0] === "keygen");
    for (const step of steps) {
      if (step.kind === "uc") {
        const env = { ...baseEnvironment };
        for (const [key, value] of Object.entries(step.env)) env[key] = concrete(value);
        const result = spawnSync(process.execPath, [cliEntry, ...step.args.map(concrete)], { cwd, encoding: "utf8", env });
        const minted = step.args[0] === "keygen" ? withoutMintedKeys : (text) => text;
        runs.push({ stdout: minted(placeholders(result.stdout)), stderr: placeholders(result.stderr), status: result.status });
      } else if (step.kind === "write") {
        mkdirSync(dirname(join(root, step.path)), { recursive: true });
        writeFileSync(join(root, step.path), step.content);
      } else if (step.kind === "edit") {
        const path = join(root, step.path);
        const before = readFileSync(path, "utf8");
        if (!before.includes(step.from)) throw new Error(`${name}: ${step.path} lacks ${step.from}`);
        writeFileSync(path, before.split(step.from).join(step.to));
      } else if (step.kind === "remove") {
        rmSync(join(root, step.path));
      } else if (step.kind === "git") {
        runGit(step.args);
      }
    }
    recorded.push({
      name,
      setup: {
        git: setup.git,
        files: Object.entries(setup.files).map(([path, content]) => ({ path, content }))
      },
      steps,
      runs,
      tree_after: tree(root).map((entry) =>
        entry.kind !== "file"
          ? entry
          : { ...entry, content: runsKeygen ? withoutMintedKeys(placeholders(entry.content)) : placeholders(entry.content) }
      )
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(cwd, { recursive: true, force: true });
  }
}

const json = escapeNonAscii(JSON.stringify({ generated_at: GEN, later: LATER, cases: recorded }));
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
// each step of each marker-command case.
//
// Regenerate with:
//   pnpm build
//   node UseCasesCLI/Scripts/generate-marker-commands-corpus.mjs
enum MarkerCommandsGoldenCorpus {
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
const target = join(outputDirectory, "MarkerCommandsGoldenCorpus.swift");
writeFileSync(target, swift);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("MarkerCommandsGoldenCorpus.swift is not ASCII");
}
console.log(`wrote ${recorded.length} cases to ${target}`);
