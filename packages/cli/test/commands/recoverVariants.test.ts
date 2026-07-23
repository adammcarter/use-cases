import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import { runCli } from "../../src/index.js";

// Regression (found in the 0.5.0 review): `uc recover --all` derived its target
// row ids from the VERIFY results — which for a variant family are keyed
// `<family>::<key>` — and then looked them up in the SCAN rows, which are keyed
// only by family ids. Every variant lookup missed, so `recover --all` reported
// not-green for the whole run the moment one variant family existed, even when
// every verifier passed and scan was fully green. Targets must be resolved at
// the family level (the unit scan actually reports on).

const CONFIG_YAML = `schema_version: 1
workspace_id: recover.variants.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: recover-variants
default_workflow_mode: continuous
`;

// One variant FAMILY (all variants pass; the command carries the required
// {variant} token) plus one ordinary row, so the fix is proven for the mixed
// matrix, not just the family-only shape.
const USE_CASE_YAML = `schema_version: 1
feature:
  id: cart
  name: Cart
  summary: Cart behaviours.
use_cases:
  - id: cart.quantity
    title: Cart quantity across input shapes
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: Set a cart quantity.
    preconditions: [Cart exists.]
    trigger: Shopper sets a quantity.
    scenarios:
      - id: cart.quantity.cli
        kind: steps
        steps: [Set a quantity.]
    observable_outcomes: [The cart reflects the quantity.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        journey:
          kind: script
          evidence_kind: test_result
          command: [sh, -c, "true # {variant}"]
          inputs: []
      requirements:
        - evidence_kind: test_result
          required_verifiers: [journey]
          minimum_count: 1
    approval_policy:
      mode: none
    variants:
      - key: zero
      - key: one
      - key: many
  - id: cart.remove
    title: Remove an item
    lifecycle: active
    value_tier: core
    journey_role: alternate
    usage_frequency: occasional
    actor: shopper
    intent: Remove an item.
    preconditions: [Cart has an item.]
    trigger: Shopper removes an item.
    scenarios:
      - id: cart.remove.cli
        kind: steps
        steps: [Remove an item.]
    observable_outcomes: [The item is gone.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        journey:
          kind: script
          evidence_kind: test_result
          command: [sh, -c, "true"]
          inputs: []
      requirements:
        - evidence_kind: test_result
          required_verifiers: [journey]
          minimum_count: 1
    approval_policy:
      mode: none
`;

// No line of THIS file may begin with the marker comment prefix: a repo-root
// `uc scan` reads fixture markers as real bindings (literal cart.* markers
// here broke the use-cases integrity workflow on main). Building the fixture
// from joined fragments keeps the written temp file byte-identical while this
// source stays invisible to the scanner.
const MARKER_PREFIX = "//" + ": @use-case:";
const SOURCE = [
  `${MARKER_PREFIX}cart.quantity`,
  "export const quantity = 1;",
  `${MARKER_PREFIX}end cart.quantity`,
  "",
  `${MARKER_PREFIX}cart.remove`,
  "export const remove = 1;",
  `${MARKER_PREFIX}end cart.remove`,
  ""
].join("\n");

const tempDirs: string[] = [];
afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) rmSync(dir, { recursive: true, force: true });
  }
});

function makeWorkspace(): string {
  const root = mkdtempSync(join(tmpdir(), "uc-recover-variants-"));
  tempDirs.push(root);
  const write = (rel: string, body: string) => {
    const full = join(root, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, body);
  };
  write("use-cases.yml", CONFIG_YAML);
  write("use-cases/cart.yml", USE_CASE_YAML);
  write("src/cart.ts", SOURCE);
  return root;
}

function run(argv: string[]): { exit: number; out: string } {
  let out = "";
  const spy = vi.spyOn(process.stdout, "write").mockImplementation((chunk: unknown) => {
    out += String(chunk);
    return true;
  });
  try {
    const exit = runCli(argv);
    return { exit, out };
  } finally {
    spy.mockRestore();
  }
}

describe("recover --all with a variant family (0.5.0 regression)", () => {
  test("a fully green mixed matrix recovers: family targets resolve at family level", () => {
    const root = makeWorkspace();
    expect(
      run(["bind", "--repo", root, "--row", "cart.quantity", "--file", "src/cart.ts", "--register-existing"]).exit
    ).toBe(0);
    expect(
      run(["bind", "--repo", root, "--row", "cart.remove", "--file", "src/cart.ts", "--register-existing"]).exit
    ).toBe(0);

    const result = run(["recover", "--repo", root, "--all", "--json"]);
    const envelope = JSON.parse(result.out);

    // Every verifier passes and scan is green — recover must say so.
    expect(envelope.data.recovered).toBe(true);
    expect(result.exit).toBe(0);
    // The verify step really did fan out per variant (3 family records + 1 ordinary).
    expect(envelope.data.verify.results).toHaveLength(4);
  });
});
