// Shared fixtures for the Phase 9 lie-guard + walking-skeleton suites.
//
// NOT a test file (no `.test.ts` suffix), so vitest never runs it directly. It
// provides a real on-disk tmp workspace (two registered use-case rows), a single
// generated ed25519 keypair standing in for the trusted-CI signer, an injected
// clock/id factory, and pass/fail verification runners — so the CLI command cores
// run end to end without shelling out to git or a real CI signer.
import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  singleKeyResolver,
  type ProveCommandOptions
} from "../../src/markers/index.js";

// The env var that gates prove's dangerous "assume verification passed" seam.
export const ALLOW_UNSAFE_ENV = "UCM_ALLOW_UNSAFE_VERIFICATION";

export const ROW_ID = "checkout.apply_coupon";
export const ROW_ID_2 = "checkout.remove_coupon";
export const GENERATED_AT = "2026-06-28T12:10:00.000Z";

// Two addressable rows: the walking-skeleton primary row plus a second properly
// registered row used by the re-slug bypass test (spec 13.9).
export const TWO_ROW_YAML = `schema_version: 1
feature:
  id: checkout
  name: Checkout
  summary: Shoppers can apply and remove coupons during checkout.
metadata:
  owner: product
  lifecycle: active
use_cases:
  - id: ${ROW_ID}
    title: Apply a valid coupon
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: Apply a valid coupon to a cart.
    preconditions:
      - A cart exists.
      - A coupon exists.
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: ${ROW_ID}.web
        kind: steps
        steps:
          - The shopper submits a coupon code.
          - The system applies the discount.
    observable_outcomes:
      - The cart total reflects the discount.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: live_demo
          required_verifiers: [user]
          minimum_count: 1
    approval_policy:
      mode: predefined
      requirements:
        - approver_type: user
          minimum_count: 1
      statement: Final acceptance requires user-visible proof.
  - id: ${ROW_ID_2}
    title: Remove a coupon
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: Remove a coupon from a cart.
    preconditions:
      - A cart exists.
      - A coupon is applied.
    trigger: The shopper removes a coupon code.
    scenarios:
      - id: ${ROW_ID_2}.web
        kind: steps
        steps:
          - The shopper removes the coupon code.
          - The system reverts the discount.
    observable_outcomes:
      - The cart total reverts to the undiscounted amount.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: live_demo
          required_verifiers: [user]
          minimum_count: 1
    approval_policy:
      mode: predefined
      requirements:
        - approver_type: user
          minimum_count: 1
      statement: Final acceptance requires user-visible proof.
`;

export const CONFIG_YAML = `schema_version: 1
workspace_id: markers.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: presentation-skills
default_workflow_mode: continuous
`;

// The spec 13.2 walking-skeleton Swift source. `@MainActor` sits on line 3, so a
// `bind --mode swift-func --line 3` inserts the marker immediately before it.
export const SWIFT_FUNC_SOURCE = `import Foundation

@MainActor
public func applyCoupon(_ code: String) async throws -> Int {
    return 1
}
`;

const keypair = generateKeyPairSync("ed25519");
export const PUBLIC_KEY: KeyObject = keypair.publicKey;
export const PRIVATE_KEY: KeyObject = keypair.privateKey;
export const KEY_ID = "trusted-ci-test";
export const resolver = singleKeyResolver(PUBLIC_KEY);

const tempDirs: string[] = [];

// Call from an afterEach in each suite to remove every tmp workspace.
export function cleanupWorkspaces(): void {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
}

export interface Workspace {
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  context: ReturnType<typeof resolveWorkspaceContext>;
}

export function writeWorkspaceFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

export function makeWorkspace(sourceFiles: Record<string, string> = {}): Workspace {
  const root = mkdtempSync(join(tmpdir(), "ucm-p9-"));
  tempDirs.push(root);
  writeWorkspaceFile(root, "presentation-skills.yml", CONFIG_YAML);
  writeWorkspaceFile(root, "use-cases/checkout.yml", TWO_ROW_YAML);
  for (const [relPath, contents] of Object.entries(sourceFiles)) {
    writeWorkspaceFile(root, relPath, contents);
  }
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  return {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "evidence.jsonl"),
    context
  };
}

export function makeClock(): () => string {
  return () => GENERATED_AT;
}

let idCounter = 0;
export function makeId(prefix: string): () => string {
  return () => `${prefix}${String(idCounter++).padStart(26 - prefix.length, "0")}`;
}

export type ProveBase = Omit<
  ProveCommandOptions,
  "trustedCi" | "signingKey"
>;
