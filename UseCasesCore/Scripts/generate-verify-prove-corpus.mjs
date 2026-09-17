// Regenerates `Tests/UseCasesCoreTests/Markers/Commands/VerifyProveGoldenCorpus.swift`
// by running every case below through the REAL TypeScript command cores in
// `packages/core/dist/markers/cli` and recording exactly what they return.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-verify-prove-corpus.mjs
//
// This is the oracle for verify and prove (row 3d4c). Each case has a SETUP the
// TypeScript alone runs (bind, verify, prove, writes) whose resulting files
// become the case's `entries`; then STEPS the Swift test replays too (write,
// git, verify, prove). The verifier process is SCRIPTED on both sides: a step
// names the outcome for each argv, and every request the runner received is
// recorded. The clock, event ids, generatedAt, the signing key and the run key
// are fixed. After every command step the whole temporary tree is recorded.
// The temporary root is recorded as `<ROOT>` everywhere.
// The script refuses to run against a `dist` older than its `src`.
//
// THIS SCRIPT WRITES MARKERS FOR A LIVING. No line of this file, and no line of
// the file it generates, may begin with a marker: marker text is built at
// runtime below, and the corpus is emitted as ONE line of escaped JSON.
import { createPrivateKey, createPublicKey } from "node:crypto";
import { execFileSync } from "node:child_process";
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
const sourceDirectory = join(repositoryRoot, "packages/core/src");
const distDirectory = join(repositoryRoot, "packages/core/dist");
const targetPath = join(
  packageRoot,
  "Tests/UseCasesCoreTests/Markers/Commands/VerifyProveGoldenCorpus.swift"
);

const PORTED = [
  "markers/cli/io",
  "markers/cli/shared",
  "markers/cli/scan",
  "markers/cli/bind",
  "markers/cli/verify",
  "markers/cli/prove",
  "markers/scanner",
  "markers/registry",
  "markers/freshness",
  "markers/runAttestation",
  "markers/verificationContextHash",
  "markers/verifierResolver",
  "markers/verifierPresets",
  "markers/evidenceLedger",
  "markers/appendOnly",
  "markers/proofSignature",
  "markers/ciAuthority",
  "markers/rowHash",
  "markers/bindingSetHash",
  "markers/policyHash",
  "markers/canonicalJson",
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

// No TypeScript call below may read or mint the real home directory's run key.
const NOWHERE_RUN_KEY = join(tmpdir(), "uc-verify-prove-no-run-key", "run-key");
process.env.UC_RUN_KEY_FILE = NOWHERE_RUN_KEY;
delete process.env.UCM_ALLOW_UNSAFE_VERIFICATION;

const core = await import(join(distDirectory, "index.js"));
const {
  resolveWorkspaceContext,
  runBindCommand,
  runVerifyCommand,
  runProveCommand,
  detectCiAuthority,
  singleKeyResolver
} = core;

// A marker line, built at runtime so this file never carries one literally.
const token = (prefix) => `${prefix}: @use-` + "case:";
const startMarker = (prefix, slug) => `${token(prefix)}${slug}`;
const endMarker = (prefix, slug) => `${token(prefix)}end ${slug}`;

const plain = (value) => (value === undefined ? null : JSON.parse(JSON.stringify(value)));

// ---------------------------------------------------------------------------
// Fixed secrets.

const seed = Buffer.alloc(32, 9);
const privateKey = createPrivateKey({
  key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]),
  format: "der",
  type: "pkcs8"
});
const PRIVATE_KEY_PEM = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const PUBLIC_KEY_PEM = createPublicKey(privateKey).export({ type: "spki", format: "pem" }).toString();
const KEY_ID = "ci-key-1";

const RUN_KEY = "0123456789abcdef".repeat(4);
const RUN_KEY_PATH = "home/.use-cases/run-key";
const DEFAULT_RUN_KEY_PATH = "home/default-run-key";
const GENERATED_AT = "2026-09-17T12:00:00.000Z";

// ---------------------------------------------------------------------------
// Workspaces. Entries are relative to a temporary root; the workspace itself is
// `workspace/`, and run keys live in `home/`.

const ROW_A = "checkout.apply_coupon";
const ROW_B = "checkout.remove_coupon";
const ROW_C = "checkout.clear_cart";
const FAMILY = "cart.quantity";

const configYaml = (verifiers) => `schema_version: 1
workspace_id: verify.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: verify-fixture
default_workflow_mode: continuous
${verifiers ? `verifiers: ${JSON.stringify(verifiers)}\n` : ""}`;

// A verification policy requiring every named verifier, each declared inline
// unless its value is null (then it is left for the workspace to resolve).
function requirements(verifiers, evidenceKind = "test_result") {
  const declared = Object.fromEntries(Object.entries(verifiers).filter(([, value]) => value !== null));
  return {
    mode: "requirements",
    ...(Object.keys(declared).length > 0 ? { verifiers: declared } : {}),
    requirements: [
      { evidence_kind: evidenceKind, required_verifiers: Object.keys(verifiers), minimum_count: 1 }
    ]
  };
}

const script = (command, extra = {}) => ({ kind: "script", evidence_kind: "test_result", command, inputs: [], ...extra });
const echoSlug = (extra = {}) => script(["echo", "{slug}"], extra);

function rowYaml(rowId, title, policy, { variants } = {}) {
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
    trigger: The shopper acts on the cart.
    scenarios:
      - id: ${rowId}.web
        kind: steps
        steps:
          - The shopper acts on the cart.
    observable_outcomes:
      - The cart reflects the change.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy: ${JSON.stringify(policy)}
    approval_policy:
      mode: predefined
      requirements:
        - approver_type: user
          minimum_count: 1
      statement: Final acceptance requires user-visible proof.
${variants ? `    variants: ${JSON.stringify(variants.map((key) => ({ key })))}\n` : ""}`;
}

function useCaseYaml(featureId, rows) {
  return `schema_version: 1
feature:
  id: ${featureId}
  name: ${featureId}
  summary: Shoppers change their ${featureId}.
metadata:
  owner: product
  lifecycle: active
use_cases:
${rows.join("")}`;
}

const CHECKOUT_SWIFT = [
  "import Foundation",
  "",
  "struct Checkout {",
  "  func applyCoupon(_ code: String) -> Bool {",
  "    return !code.isEmpty",
  "  }",
  "",
  "  func clearCart() -> Bool {",
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

const CART_SWIFT = [
  "import Foundation",
  "",
  "func cartQuantity(_ count: Int) -> Int {",
  "  return count",
  "}",
  ""
].join("\n");

const file = (path, contents, mode = 0o644) => ["file", path, contents, mode];
const workspaceFile = (path, contents, mode = 0o644) => file(`workspace/${path}`, contents, mode);
const runKeyEntry = (path = RUN_KEY_PATH) => file(path, `${RUN_KEY}\n`, 0o600);

// The standard workspace: rows A, B and C in checkout, the variant family in
// cart. `policies` overrides a row's verification policy; `variants` the
// family's keys; `workspaceVerifiers` the config's verifiers map.
function workspaceEntries({
  a = requirements({ contract: echoSlug() }),
  b = requirements({ contract: echoSlug() }),
  c = requirements({ contract: echoSlug() }),
  family = requirements({ journey: script(["echo", "{slug}", "{variant}"]) }),
  variants = ["small", "empty", "b-2"],
  workspaceVerifiers
} = {}) {
  return [
    workspaceFile("use-cases.yml", configYaml(workspaceVerifiers)),
    workspaceFile(
      "use-cases/checkout.yml",
      useCaseYaml("checkout", [
        rowYaml(ROW_A, "Apply a valid coupon", a),
        rowYaml(ROW_B, "Remove a coupon", b),
        rowYaml(ROW_C, "Clear the cart", c)
      ])
    ),
    workspaceFile("use-cases/cart.yml", useCaseYaml("cart", [rowYaml(FAMILY, "Cart quantity", family, { variants })])),
    workspaceFile("Sources/Checkout.swift", CHECKOUT_SWIFT),
    workspaceFile("Sources/Cart.swift", CART_SWIFT),
    workspaceFile("tools/coupon.py", COUPON_PY),
    runKeyEntry()
  ];
}

function materialize(root, entries) {
  for (const entry of entries) {
    const [kind, path] = entry;
    const full = join(root, path);
    if (kind === "file") {
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

const gitIdentity = ["-c", "user.name=Use Cases", "-c", "user.email=use-cases@example.com", "-c", "commit.gpgsign=false"];

function contextFor(root) {
  return resolveWorkspaceContext({ workspaceRoot: join(root, "workspace") });
}

function ledgerPaths(context) {
  return {
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl")
  };
}

// The verification-results file as the CLI reads it for `prove`.
function readResults(path) {
  return readFileSync(path, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => JSON.parse(line));
}

// ---------------------------------------------------------------------------
// Setup actions: run by the TypeScript only; their files become the entries.

function runSetup(root, action) {
  const context = contextFor(root);
  const paths = ledgerPaths(context);
  let tick = 0;
  const clock = () => `2026-09-17T10:00:${String(tick++).padStart(2, "0")}.000Z`;
  const idFactory = () => `setup-${String(tick++).padStart(4, "0")}`;
  if (action.kind === "bind") {
    const result = runBindCommand({
      context,
      productRoot: context.workspace_root,
      bindingsPath: paths.bindingsPath,
      clock,
      idFactory,
      version: "0.7.0",
      rowId: action.row_id,
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
      outPath: join(context.data_root, ".use-cases", "verification-results.jsonl"),
      spawnRunner: (request) => outcomeFor(action.runner ?? {}, request),
      repoCwd: context.workspace_root,
      runKeyPath: join(root, RUN_KEY_PATH)
    });
    if (result.exit_code > 1) {
      throw new Error(`setup verify failed: ${JSON.stringify(result)}`);
    }
  } else if (action.kind === "prove") {
    const result = runProveCommand({
      context,
      productRoot: context.workspace_root,
      ...paths,
      publicKeyResolver: singleKeyResolver(PUBLIC_KEY_PEM),
      rowId: action.row_id,
      all: action.row_id === undefined,
      trustedCi: true,
      append: true,
      verificationResults: readResults(join(context.data_root, ".use-cases", "verification-results.jsonl")),
      signingKey: { privateKey, keyId: KEY_ID },
      producer: { id: "ucm-ci", version: "0.7.0", ci_run_id: "run-1", repo: "example/app", commit: "abc123" },
      generatedAt: GENERATED_AT,
      idFactory,
      repoCwd: context.workspace_root
    });
    if (!result.rows.some((row) => row.status === "signed")) {
      throw new Error(`setup prove signed nothing: ${JSON.stringify(result)}`);
    }
  } else if (action.kind === "write") {
    materialize(root, [file(action.path, action.contents, action.mode ?? 0o644)]);
  } else {
    throw new Error(`unknown setup ${action.kind}`);
  }
}

// ---------------------------------------------------------------------------
// The scripted verifier: an outcome per argv (joined with a space), else the
// runner's default, else a clean pass.

const PASS = { exit_code: 0, timed_out: false, stdout: "ok\n", stderr: "" };

function outcomeFor(runner, request) {
  const key = request.command.join(" ");
  return runner.outcomes?.[key] ?? runner.default ?? PASS;
}

// ---------------------------------------------------------------------------
// Steps: replayed by the Swift test.

function runVerifyStep(root, options) {
  const context = contextFor(root);
  const paths = ledgerPaths(context);
  const spawns = [];
  const runner = options.runner ?? {};
  const previous = process.env.UC_RUN_KEY_FILE;
  if (options.default_run_key) {
    process.env.UC_RUN_KEY_FILE = join(root, DEFAULT_RUN_KEY_PATH);
  }
  try {
    const result = runVerifyCommand({
      context,
      productRoot: context.workspace_root,
      ...paths,
      publicKeyResolver: options.public_key ? singleKeyResolver(PUBLIC_KEY_PEM) : () => undefined,
      trustedKeyConfigured: options.trusted_key_configured,
      generatedAt: GENERATED_AT,
      all: options.all,
      rowId: options.row,
      outPath: options.out === undefined ? undefined : options.out === "" ? "" : join(root, options.out),
      dryRun: options.dry_run,
      spawnRunner: (request) => {
        spawns.push(plain(request));
        return outcomeFor(runner, request);
      },
      baseRef: options.base_ref,
      repoCwd: context.workspace_root,
      runKeyPath: options.default_run_key ? undefined : join(root, options.run_key_path ?? RUN_KEY_PATH)
    });
    return { result: plain(result), spawns };
  } finally {
    process.env.UC_RUN_KEY_FILE = previous;
  }
}

function runProveStep(root, options) {
  const context = contextFor(root);
  const paths = ledgerPaths(context);
  let tick = 0;
  const idFactory = () => `proof-${String(tick++).padStart(4, "0")}`;
  let authority;
  if (options.authority_environment) {
    authority = detectCiAuthority(options.authority_environment);
  } else if ("authority_record" in options) {
    authority = options.authority_record;
  }
  if (options.unsafe_environment !== undefined) {
    process.env.UCM_ALLOW_UNSAFE_VERIFICATION = options.unsafe_environment;
  }
  try {
    const result = runProveCommand({
      context,
      productRoot: context.workspace_root,
      ...paths,
      publicKeyResolver: options.public_key === false ? () => undefined : singleKeyResolver(PUBLIC_KEY_PEM),
      rowId: options.row,
      all: options.all,
      refresh: options.refresh,
      trustedCi: options.trusted_ci,
      append: options.append,
      dryRun: options.dry_run,
      verificationResults: options.results_file ? readResults(join(root, options.results_file)) : undefined,
      unsafeAssumeVerificationResult: options.unsafe_assume ? "pass" : undefined,
      signingKey: options.signing_key ? { privateKey, keyId: KEY_ID } : undefined,
      producer: options.producer,
      authority,
      generatedAt: GENERATED_AT,
      idFactory,
      repoCwd: context.workspace_root
    });
    return { result: plain(result) };
  } finally {
    delete process.env.UCM_ALLOW_UNSAFE_VERIFICATION;
  }
}

function runCase(testCase) {
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-verify-prove-")));
  const placeholder = (value) => JSON.parse(JSON.stringify(value).split(temporary).join("<ROOT>"));
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
      } else if (step.kind === "git") {
        execFileSync("git", step.arguments, { cwd: join(temporary, "workspace"), stdio: "pipe" });
      } else {
        const options = step.options ?? {};
        try {
          Object.assign(
            recorded,
            step.kind === "verify" ? runVerifyStep(temporary, options) : runProveStep(temporary, options)
          );
        } catch (error) {
          recorded.thrown = { message: error instanceof Error ? error.message : String(error) };
        }
        recorded.files = snapshot(temporary);
      }
      steps.push(recorded);
    }
    return placeholder({ name: testCase.name, entries, steps });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

// Steps whose contents depend on bytes the setup produced are resolved in a
// probe run first and replayed as plain writes.
function runCaseWithDynamicSteps(testCase) {
  const temporary = realpathSync(mkdtempSync(join(tmpdir(), "uc-verify-prove-probe-")));
  try {
    materialize(temporary, testCase.entries);
    for (const action of testCase.setup ?? []) {
      runSetup(temporary, action);
    }
    const steps = testCase.steps.map((step) => {
      if (step.kind === "derive_results") {
        const text = readFileSync(join(temporary, RESULTS), "utf8");
        const records = text.split("\n").filter((line) => line.trim() !== "").map((line) => JSON.parse(line));
        return write(step.path, step.derive(records));
      }
      if (step.kind === "rewrite_first_proof") {
        const path = "workspace/.use-cases/proofs.jsonl";
        const text = readFileSync(join(temporary, path), "utf8");
        if (!text.startsWith("{")) {
          throw new Error("no proof to rewrite");
        }
        return write(path, `{ ${text.slice(1)}`);
      }
      return step;
    });
    return runCase({ ...testCase, steps });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

const RESULTS = "workspace/.use-cases/verification-results.jsonl";
const verify = (options = {}) => ({ kind: "verify", options });
const prove = (options = {}) => ({ kind: "prove", options });
const write = (path, contents, mode) => ({ kind: "write", path, contents, ...(mode ? { mode } : {}) });
const git = (...args) => ({ kind: "git", arguments: args });
const deriveResults = (path, derive) => ({ kind: "derive_results", path, derive });
const lines = (values) => values.map((value) => `${typeof value === "string" ? value : JSON.stringify(value)}\n`).join("");

const bindA = { kind: "bind", row_id: ROW_A, file: "Sources/Checkout.swift", mode: "swift-func", line: 4 };
const bindB = { kind: "bind", row_id: ROW_B, file: "tools/coupon.py", mode: "explicit", start_line: 6, end_line: 7 };
const bindC = { kind: "bind", row_id: ROW_C, file: "Sources/Checkout.swift", mode: "swift-func", line: 9 }; // after bindA
const bindFamily = { kind: "bind", row_id: FAMILY, file: "Sources/Cart.swift", mode: "swift-func", line: 3 };
const strayMarker = (slug) => ({
  kind: "write",
  path: "workspace/tools/stray.py",
  contents: `${startMarker("#", slug)}\nprint(1)\n${endMarker("#", slug)}\n`
});

const echo = (slug, ...rest) => ["echo", slug, ...rest].join(" ");
const failed = (exitCode, stderr = "boom\n") => ({ exit_code: exitCode, timed_out: false, stdout: "", stderr });

// ---------------------------------------------------------------------------
// Verify cases.

const verifyCases = [
  {
    name: "pass_fail_and_rows_preserved_across_runs",
    entries: workspaceEntries(),
    setup: [bindA, bindB],
    steps: [
      verify({
        all: true,
        out: RESULTS,
        runner: { outcomes: { [echo(ROW_B)]: { exit_code: 3, timed_out: false, stdout: "café \u{1F600}\n", stderr: "boom\n" } } }
      }),
      verify({ row: ROW_A, out: RESULTS, runner: { default: { exit_code: 0, timed_out: false, stdout: "second\n", stderr: "warn\n" } } }),
      verify({ row: ROW_B, out: RESULTS }),
      verify({ all: true })
    ]
  },
  {
    name: "timeouts_record_fail",
    entries: workspaceEntries({
      a: requirements({ contract: echoSlug({ timeout_seconds: 2.5 }) }),
      b: requirements({ contract: echoSlug({ timeout_seconds: 0.001 }) })
    }),
    setup: [bindA, bindB],
    steps: [
      verify({
        all: true,
        out: RESULTS,
        runner: {
          outcomes: {
            [echo(ROW_A)]: { exit_code: 124, timed_out: true, stdout: "partial", stderr: "" },
            [echo(ROW_B)]: { exit_code: 0, timed_out: true, stdout: "", stderr: "" }
          }
        }
      })
    ]
  },
  {
    name: "blocked_verifiers",
    entries: workspaceEntries({
      a: requirements({ missing_one: null }),
      b: { mode: "none" },
      c: requirements({ acceptance: null }),
      workspaceVerifiers: { default: "not_declared" }
    }),
    setup: [bindA, bindB, bindC],
    steps: [verify({ all: true, out: RESULTS }), verify({ all: true, dry_run: true })]
  },
  {
    name: "workspace_verifiers_resolve",
    entries: workspaceEntries({
      a: requirements({ acceptance: null }),
      b: requirements({ shared: null }),
      workspaceVerifiers: {
        default: "shared",
        shared: { kind: "script", evidence_kind: "test_result", command: ["sh", "-c", "echo {slug}"], timeout_seconds: 30 }
      }
    }),
    setup: [bindA, bindB],
    steps: [verify({ all: true, out: RESULTS })]
  },
  {
    name: "invalid_row_records_fail",
    entries: workspaceEntries(),
    setup: [bindA, strayMarker(ROW_B)],
    steps: [verify({ all: true, out: RESULTS }), verify({ row: ROW_B, out: RESULTS }), verify({ all: true, dry_run: true })]
  },
  {
    name: "variant_family_fans_out",
    entries: workspaceEntries(),
    setup: [bindA, bindFamily],
    steps: [
      verify({
        all: true,
        out: RESULTS,
        runner: { outcomes: { [echo(FAMILY, "empty")]: failed(2) } }
      }),
      verify({ row: FAMILY, dry_run: true }),
      verify({ row: FAMILY, out: RESULTS })
    ]
  },
  {
    name: "variant_family_without_token_is_blocked",
    entries: workspaceEntries({
      family: requirements({ journey: script(["echo", "{slug}"], { evidence_kind: "live_demo" }) }, "live_demo")
    }),
    setup: [bindA, bindFamily],
    steps: [verify({ all: true, out: RESULTS }), verify({ all: true, dry_run: true })]
  },
  {
    name: "invalid_variant_family_raises_no_token_error",
    entries: workspaceEntries({
      family: requirements({ journey: script(["echo", "{slug}"]) })
    }),
    setup: [bindA, strayMarker(FAMILY)],
    steps: [verify({ all: true, out: RESULTS }), verify({ all: true, dry_run: true })]
  },
  {
    name: "variant_family_with_a_blocked_verifier",
    entries: workspaceEntries({ family: requirements({ nowhere: null }), variants: ["only"] }),
    setup: [bindFamily],
    steps: [verify({ row: FAMILY, out: RESULTS }), verify({ row: FAMILY, dry_run: true })]
  },
  {
    name: "dry_run_plans_spawns_nothing_and_writes_nothing",
    entries: [
      ...workspaceEntries({
        a: requirements({ unit: echoSlug(), zeta: script(["make", "{slug}"]) }),
        c: requirements({ missing: null })
      }),
      workspaceFile(".use-cases/verification-results.jsonl", '{"row_id":"kept.row","status":"pass"}\n')
    ],
    setup: [bindA, bindC],
    steps: [
      verify({ all: true, dry_run: true, out: RESULTS, run_key_path: "home/never-minted" }),
      verify({ row: ROW_A, dry_run: true, out: RESULTS, run_key_path: "home/never-minted" }),
      verify({ row: ROW_B, dry_run: true })
    ]
  },
  {
    name: "targets_and_refusals",
    entries: workspaceEntries(),
    setup: [bindA],
    steps: [
      verify({}),
      verify({ row: "" }),
      verify({ row: "", all: true, out: "" }),
      verify({ row: "no.such_row", all: true }),
      verify({ row: ROW_B, out: "workspace/.use-cases/empty-results.jsonl", run_key_path: "home/unminted" })
    ]
  },
  {
    name: "results_ledger_merge_keeps_other_rows",
    entries: [
      ...workspaceEntries(),
      workspaceFile(
        ".use-cases/verification-results.jsonl",
        lines([
          "",
          "   ",
          "not json",
          "[1]",
          "null",
          "42",
          { row_id: 5, status: "pass" },
          `  {"row_id":"zzz.other", "status":"pass","extra":{"b":1,"a":2}}  `,
          { row_id: ROW_A, status: "fail", stale: true },
          { row_id: "é.accented", status: "pass" },
          { row_id: "Z.upper", status: "pass" },
          { row_id: "zzz.other", status: "fail", duplicate: true },
          { row_id: "\u{1F600}.astral", status: "pass" },
          { row_id: "｡.halfwidth", status: "pass" },
          "{\"row_id\":\"a.no_newline\"}"
        ]).trimEnd()
      )
    ],
    setup: [bindA],
    steps: [verify({ row: ROW_A, out: RESULTS })]
  },
  {
    name: "overclaim_and_the_decisive_verifier",
    entries: workspaceEntries({
      a: requirements({ suite: { preset: "js.vitest", evidence_kind: "live_demo" } }, "live_demo"),
      b: requirements({ a_unit: { preset: "python.pytest" }, b_demo: script(["demo", "{slug}"], { evidence_kind: "live_demo" }) }),
      c: requirements({ go: { preset: "go.test", evidence_kind: "live_demo" }, make: { preset: "make.target", evidence_kind: "live_demo" } }, "live_demo")
    }),
    setup: [bindA, bindB, bindC],
    steps: [
      verify({ all: true, out: RESULTS, runner: { outcomes: { [`demo ${ROW_B}`]: failed(1) } } }),
      verify({ all: true, dry_run: true }),
      verify({ row: ROW_C, runner: { default: failed(9) } })
    ]
  },
  {
    name: "missing_public_key_and_damaged_ledgers",
    entries: workspaceEntries(),
    setup: [bindA, { kind: "verify" }, { kind: "prove" }],
    steps: [
      verify({ all: true, trusted_key_configured: false }),
      verify({ all: true }),
      verify({ all: true, trusted_key_configured: true }),
      verify({ all: true, public_key: true }),
      write("workspace/.use-cases/proofs.jsonl", '{"schema":"ucase-proof-event-v1"}\n'),
      verify({ all: true, trusted_key_configured: false }),
      write("workspace/.use-cases/bindings.jsonl", "{not json\n"),
      verify({ all: true, trusted_key_configured: false })
    ]
  },
  {
    name: "default_run_key_location",
    entries: [...workspaceEntries(), runKeyEntry(DEFAULT_RUN_KEY_PATH)],
    setup: [bindA],
    steps: [verify({ all: true, out: RESULTS, default_run_key: true })]
  },
  {
    name: "rewritten_evidence_ledger_passes_the_base_ref_check",
    entries: workspaceEntries(),
    setup: [bindA, { kind: "verify" }, { kind: "prove" }],
    steps: [
      git("init", "-q", "-b", "main"),
      git("add", "-A"),
      git(...gitIdentity, "commit", "-q", "-m", "base"),
      { kind: "rewrite_first_proof" },
      verify({ all: true, public_key: true, base_ref: "HEAD" }),
      prove({ all: true, base_ref: "HEAD", results_file: RESULTS })
    ]
  }
];

// ---------------------------------------------------------------------------
// Prove cases.

const passingSetup = [bindA, bindB, bindC, bindFamily, { kind: "verify", runner: { outcomes: { [echo(ROW_C)]: failed(1) } } }];
const producer = { id: "ucm-ci", version: "9.9.9", ci_run_id: "run-7", repo: "example/app", commit: "f".repeat(40) };

const recordFor = (records, rowId) => records.find((record) => record.row_id === rowId);

const proveCases = [
  {
    name: "refusals_in_order",
    entries: workspaceEntries(),
    setup: passingSetup,
    steps: [
      prove({ append: true }),
      prove({ append: true, trusted_ci: true }),
      prove({}),
      prove({ row: "" }),
      prove({ row: "no.such_row", all: true, trusted_ci: true, signing_key: true }),
      prove({ row: "no.such_row", trusted_ci: true }),
      prove({ row: ROW_A, trusted_ci: true }),
      prove({ all: true, trusted_ci: true, dry_run: true, results_file: RESULTS }),
      prove({ row: "", all: true, results_file: RESULTS })
    ]
  },
  {
    name: "ledger_invalid_without_a_key",
    entries: workspaceEntries(),
    setup: [...passingSetup, { kind: "prove", row_id: ROW_A }],
    steps: [prove({ all: true, public_key: false, results_file: RESULTS }), prove({ row: ROW_A, results_file: RESULTS })]
  },
  {
    name: "untrusted_sweep_row_statuses",
    entries: workspaceEntries(),
    setup: [...passingSetup, strayMarker(ROW_B)],
    steps: [
      prove({ all: true, results_file: RESULTS }),
      prove({ all: true }),
      prove({ row: FAMILY, results_file: RESULTS }),
      prove({ row: ROW_B, results_file: RESULTS })
    ]
  },
  {
    name: "result_records_are_checked",
    entries: workspaceEntries(),
    setup: passingSetup,
    steps: [
      deriveResults("workspace/blocked.jsonl", (records) => lines([{ ...recordFor(records, ROW_A), status: "blocked" }])),
      prove({ row: ROW_A, results_file: "workspace/blocked.jsonl" }),
      deriveResults("workspace/latest.jsonl", (records) =>
        lines([recordFor(records, ROW_A), { ...recordFor(records, ROW_A), status: "fail" }])
      ),
      prove({ row: ROW_A, results_file: "workspace/latest.jsonl" }),
      deriveResults("workspace/mismatch.jsonl", (records) =>
        lines([
          {
            ...recordFor(records, ROW_A),
            row_hash: "sha256:0",
            binding_set_hash: 7,
            span_sha256s: [...recordFor(records, ROW_A).span_sha256s, "extra"],
            verification_context_hash: null
          }
        ])
      ),
      prove({ row: ROW_A, results_file: "workspace/mismatch.jsonl" }),
      deriveResults("workspace/span-string.jsonl", (records) =>
        lines([{ ...recordFor(records, ROW_A), span_sha256s: "abc" }, 42, "\"text\"", [1]])
      ),
      prove({ row: ROW_A, results_file: "workspace/span-string.jsonl" }),
      deriveResults("workspace/span-object.jsonl", (records) =>
        lines([{ ...recordFor(records, ROW_A), span_sha256s: { length: 1 } }])
      ),
      prove({ row: ROW_A, results_file: "workspace/span-object.jsonl" }),
      deriveResults("workspace/span-string-same-length.jsonl", (records) =>
        lines([{ ...recordFor(records, ROW_A), span_sha256s: "x" }])
      ),
      prove({ row: ROW_A, results_file: "workspace/span-string-same-length.jsonl" }),
      deriveResults("workspace/span-absent.jsonl", (records) => {
        const { span_sha256s: _dropped, ...rest } = recordFor(records, ROW_A);
        return lines([rest]);
      }),
      prove({ row: ROW_A, results_file: "workspace/span-absent.jsonl" }),
      write("workspace/null.jsonl", "null\n"),
      prove({ row: ROW_A, results_file: "workspace/null.jsonl" }),
      deriveResults("workspace/odd-fields.jsonl", (records) => {
        const { created_at: _dropped, ...rest } = recordFor(records, ROW_A);
        return lines([{ ...rest, verifier_id: 12 }]);
      }),
      prove({ row: ROW_A, trusted_ci: true, signing_key: true, results_file: "workspace/odd-fields.jsonl" })
    ]
  },
  {
    name: "trusted_append_chains_signs_and_skips_fresh",
    entries: workspaceEntries(),
    setup: passingSetup,
    steps: [
      prove({
        all: true,
        trusted_ci: true,
        append: true,
        signing_key: true,
        producer,
        authority_environment: {
          GITHUB_ACTIONS: "true",
          GITHUB_REPOSITORY: "example/app",
          GITHUB_REF: "refs/heads/main",
          GITHUB_SHA: "f".repeat(40),
          GITHUB_RUN_ID: "77",
          GITHUB_ACTOR: "octo",
          GITHUB_EVENT_NAME: "push"
        },
        results_file: RESULTS
      }),
      prove({ all: true, trusted_ci: true, signing_key: true, results_file: RESULTS }),
      prove({ row: ROW_A, refresh: true, trusted_ci: true, signing_key: true, results_file: RESULTS })
    ]
  },
  {
    name: "producer_defaults_without_authority",
    entries: workspaceEntries(),
    setup: passingSetup,
    steps: [prove({ row: ROW_A, trusted_ci: true, signing_key: true, results_file: RESULTS })]
  },
  {
    name: "empty_producer_fields_and_a_null_authority_record",
    entries: workspaceEntries(),
    setup: passingSetup,
    steps: [
      prove({
        row: ROW_A,
        trusted_ci: true,
        signing_key: true,
        results_file: RESULTS,
        producer: { ci_run_id: "", repo: "only/repo" },
        authority_record: null
      })
    ]
  },
  {
    name: "authority_record_passes_through",
    entries: workspaceEntries(),
    setup: passingSetup,
    steps: [
      prove({
        row: ROW_A,
        trusted_ci: true,
        signing_key: true,
        results_file: RESULTS,
        authority_record: { type: "local", provider: "generic", note: "from a file" }
      })
    ]
  },
  {
    name: "authority_detected_outside_ci",
    entries: workspaceEntries(),
    setup: passingSetup,
    steps: [
      prove({ row: ROW_A, trusted_ci: true, signing_key: true, results_file: RESULTS, authority_environment: {} }),
      prove({ all: true, refresh: true, trusted_ci: true, signing_key: true, results_file: RESULTS, authority_environment: {} })
    ]
  },
  {
    name: "unsafe_assumption_needs_the_environment",
    entries: workspaceEntries(),
    setup: [bindA],
    steps: [
      prove({ row: ROW_A, unsafe_assume: true }),
      prove({ row: ROW_A, unsafe_assume: true, unsafe_environment: "true" }),
      prove({ row: ROW_A, unsafe_assume: true, unsafe_environment: "1" }),
      prove({ row: ROW_A, unsafe_environment: "1" }),
      prove({ row: ROW_A, unsafe_assume: true, unsafe_environment: "1", trusted_ci: true, signing_key: true }),
      prove({ all: true, unsafe_assume: true, unsafe_environment: "1" })
    ]
  },
  {
    name: "dry_runs_append_nothing",
    entries: workspaceEntries(),
    setup: passingSetup,
    steps: [
      prove({ all: true, dry_run: true, results_file: RESULTS }),
      prove({ all: true, dry_run: true, trusted_ci: true, signing_key: true, results_file: RESULTS })
    ]
  }
];

const verifyResults = verifyCases.map(runCaseWithDynamicSteps);
const proveResults = proveCases.map(runCaseWithDynamicSteps);

// Guard the fixtures: a case meant to exercise a status must actually reach it.
const statusesSeen = new Set(
  [...verifyResults, ...proveResults].flatMap((entry) =>
    entry.steps.flatMap((step) => [
      ...(step.result?.results ?? []).map((record) => `verify:${record.status}`),
      ...(step.result?.planned ?? []).map((plan) => `plan:${plan.disposition}`),
      ...(step.result?.rows ?? []).map((row) => `prove:${row.status}:${row.reason}`),
      ...(step.thrown ? ["thrown"] : [])
    ])
  )
);
for (const expected of [
  "verify:pass",
  "verify:fail",
  "verify:blocked",
  "plan:run",
  "plan:blocked",
  "plan:invalid",
  "prove:signed:null",
  "prove:candidate:null",
  "prove:skipped_unbound:null",
  "prove:skipped_fresh:null",
  "prove:skipped_variant_family:VARIANT_FAMILY_UNSUPPORTED",
  "prove:failed:VARIANT_FAMILY_UNSUPPORTED",
  "prove:failed:ROW_INVALID",
  "prove:failed:NO_PASSING_RESULT",
  "prove:failed:RESULT_BLOCKED",
  "prove:failed:RESULT_FAILED",
  "prove:failed:HASH_MISMATCH",
  "thrown"
]) {
  if (!statusesSeen.has(expected)) {
    throw new Error(`no case reaches ${expected}`);
  }
}

// ---------------------------------------------------------------------------
// Emit.

const corpus = {
  public_key_pem: PUBLIC_KEY_PEM,
  private_key_pem: PRIVATE_KEY_PEM,
  key_id: KEY_ID,
  run_key: RUN_KEY,
  run_key_path: RUN_KEY_PATH,
  default_run_key_path: DEFAULT_RUN_KEY_PATH,
  generated_at: GENERATED_AT,
  verify_cases: verifyResults,
  prove_cases: proveResults
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
// Generated from the TypeScript verify and prove cores. DO NOT EDIT BY HAND.
//
// Every expected value is what packages/core/dist/markers/cli returned for the
// input beside it. The temporary root is spelled <ROOT>.
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-verify-prove-corpus.mjs
enum VerifyProveGoldenCorpus {
${nameList("verifyCaseNames", verifyResults)}
${nameList("proveCaseNames", proveResults)}
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
console.log(`wrote ${targetPath}: ${verifyResults.length} verify, ${proveResults.length} prove cases`);
