// A spawned verifier is not a demonstration, whatever the row calls it.
//
// Measured on a real repo: 42 of 297 rows resolved to nothing but a unit-suite
// filter, and every one of them recorded `evidence_kind: live_demo`. The field
// was copied verbatim from the row's own verifier declaration and never
// questioned, so the ledger carried the author's word for what the evidence was
// worth. The repo's own runner header concedes a unit suite is "WEAKER evidence
// than a journey"; the ledger said nothing of the sort.
//
// `verify` now records what it can SEE — the shape of the verifier it actually
// resolved and spawned — beside what the row DECLARED, and says so when the two
// disagree. It can never mint a journey: it spawns a process, and a process is
// not a demonstration. A demonstration is `use-cases evidence record --perform`.
import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { generateKeyPairSync } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runVerifyCommand,
  singleKeyResolver,
  type VerifySpawnRunner
} from "../../src/markers/index.js";

const GENERATED_AT = "2026-06-28T12:10:00.000Z";
const resolver = singleKeyResolver(generateKeyPairSync("ed25519").publicKey);
const tempDirs: string[] = [];

afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

const CONFIG_YAML = `schema_version: 1
workspace_id: markers.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: presentation-skills
default_workflow_mode: continuous
`;

const SWIFT = `import Foundation

@MainActor
public func applyCoupon(_ code: String) async throws -> Int {
    return 1
}
`;

// One row whose verifier is whatever the caller specifies, declaring whatever
// evidence_kind the caller specifies. Both halves of the lie are parameters.
function useCaseYaml(rowId: string, verifierBlock: string): string {
  return `schema_version: 1
feature:
  id: checkout
  name: Checkout
  summary: Shoppers can apply coupons during checkout.
metadata:
  owner: product
  lifecycle: active
use_cases:
  - id: ${rowId}
    title: Apply a valid coupon
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: Apply a valid coupon to a cart.
    preconditions:
      - A cart exists.
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: ${rowId}.web
        kind: steps
        steps:
          - The shopper submits a coupon code.
    observable_outcomes:
      - The cart total reflects the discount.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
${verifierBlock}
      requirements:
        - evidence_kind: test_result
          required_verifiers: [checker]
          minimum_count: 1
    approval_policy:
      mode: none
`;
}

const ROW = "checkout.apply_coupon";

function verifyWith(verifierBlock: string) {
  const root = mkdtempSync(join(tmpdir(), "ucm-runclass-"));
  tempDirs.push(root);
  for (const [rel, body] of [
    ["use-cases.yml", CONFIG_YAML],
    ["use-cases/checkout.yml", useCaseYaml(ROW, verifierBlock)],
    ["Sources/Checkout/CouponService.swift", SWIFT]
  ] as const) {
    const full = join(root, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, body);
  }
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  const bindingsPath = join(context.data_root, ".use-cases", "bindings.jsonl");
  const evidencePath = join(context.data_root, ".use-cases", "proofs.jsonl");
  expect(
    runBindCommand({
      context,
      productRoot: context.workspace_root,
      bindingsPath,
      rowId: ROW,
      file: "Sources/Checkout/CouponService.swift",
      mode: "swift-func",
      line: 3,
      clock: () => GENERATED_AT,
      idFactory: () => "01JBIND000000000000000000"
    }).exit_code
  ).toBe(0);

  const passSpawn: VerifySpawnRunner = () => ({
    exit_code: 0,
    timed_out: false,
    stdout: "ok\n",
    stderr: ""
  });
  return runVerifyCommand({
    context,
    productRoot: context.workspace_root,
    bindingsPath,
    evidencePath,
    publicKeyResolver: resolver,
    trustedKeyConfigured: false,
    generatedAt: GENERATED_AT,
    rowId: ROW,
    runKeyPath: join(root, "machine", "run-key"),
    spawnRunner: passSpawn
  });
}

const PYTEST_PRESET = `        checker:
          preset: python.pytest
          evidence_kind: live_demo
`;
const HONEST_PRESET = `        checker:
          preset: python.pytest
          evidence_kind: test_result
`;
// A preset that is NOT a test runner. `make test-use-case SLUG=…` may genuinely
// drive the shipped product, and the tool cannot tell from outside — so it must
// NOT be called a suite, and must NOT be flagged for declaring a demo.
const MAKE_PRESET = `        checker:
          preset: make.target
          evidence_kind: live_demo
`;
const SCRIPT_VERIFIER = `        checker:
          kind: script
          evidence_kind: live_demo
          command: [./scripts/drive-checkout.sh]
          inputs: []
`;

describe("the ledger records what ran, not what the row called it", () => {
  test("a test-suite preset records run_class `suite`", () => {
    const record = verifyWith(HONEST_PRESET).results[0];
    expect(record.run_class).toBe("suite");
  });

  test("an arbitrary script records run_class `command`, never `suite`", () => {
    const record = verifyWith(SCRIPT_VERIFIER).results[0];
    expect(record.run_class).toBe("command");
  });

  // The measured lie, at unit scale.
  test("a unit-suite preset declaring itself a live_demo is recorded as overclaimed", () => {
    const record = verifyWith(PYTEST_PRESET).results[0];
    // The declaration is preserved — the ledger corrects nobody's YAML.
    expect(record.evidence_kind).toBe("live_demo");
    // …and the derived truth sits beside it.
    expect(record.run_class).toBe("suite");
    expect(record.evidence_kind_overclaimed).toBe(true);
  });

  test("verify names the overclaiming rows so the author sees them", () => {
    expect(verifyWith(PYTEST_PRESET).overclaimed_rows).toEqual([ROW]);
  });

  // Isolating this mattered: a first version of the suite only ever exercised a
  // test-runner preset and an explicit script, so widening `isTestSuitePreset`
  // to "every preset" broke nothing at all.
  test("a non-runner preset is a command, and its live_demo claim stands", () => {
    const record = verifyWith(MAKE_PRESET).results[0];
    expect(record.run_class).toBe("command");
    expect(record.evidence_kind_overclaimed).toBe(false);
  });

  test("an honest row is not flagged", () => {
    const result = verifyWith(HONEST_PRESET);
    expect(result.results[0].evidence_kind_overclaimed).toBe(false);
    expect(result.overclaimed_rows).toEqual([]);
  });

  // A script CAN be a real drive of the product, so `command` + live_demo is not
  // itself a lie. The overclaim rule fires only where the tool can PROVE the
  // declaration wrong: a named test-runner preset is a test suite by definition.
  test("a script declaring live_demo is left alone — the tool cannot prove that wrong", () => {
    expect(verifyWith(SCRIPT_VERIFIER).results[0].evidence_kind_overclaimed).toBe(false);
  });
});
