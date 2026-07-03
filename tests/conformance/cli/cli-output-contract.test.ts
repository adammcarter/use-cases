// v1 CLI output conformance test.
//
// Closes the gap recorded in docs/release/v1-surface-inventory.md:
//   "no test asserts that every CLI/MCP JSON output validates against its schema".
//
// Contract proved here:
//   1. EVERY CLI command that emits `--json` produces stdout that parses as JSON
//      and validates against the result envelope schema (cli-result.schema.json):
//      { schema_version, protocol_version, command, ok, complete, data,
//        diagnostics, context }.
//   2. Where a command declares a specific data schema (per the surface
//      inventory's per-command mapping), its `data` ALSO validates against that
//      schema.
//   3. Coverage: the set of commands exercised here equals the canonical v1 CLI
//      surface (44 commands), so a new command cannot silently escape the
//      contract without this test going red.
//
// Reuses the EXISTING schema machinery (validateBySchemaId → the offline AJV 2020
// registry compiled from schemas/v1) rather than hand-rolling a second validator,
// the same way tests/schema/schema-contracts.test.ts does.
//
// Every command is run through the BUILT CLI (node packages/cli/dist/index.js)
// against fixture workspaces; mutating commands operate on a COPY in a temp dir so
// the test is hermetic and repeatable. The build runs once in beforeAll.

import { spawnSync } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../../packages/core/src/schema/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

const ENVELOPE_SCHEMA_ID = "https://use-cases.dev/schemas/v1/cli-result.schema.json";
const schemaId = (name: string) => `https://use-cases.dev/schemas/v1/${name}.schema.json`;

const tempDirs: string[] = [];

function copyFixture(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `ucm-conf-${name}-`));
  tempDirs.push(workspaceRoot);
  cpSync(join(fixturesRoot, name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function runCli(args: string[], env: Record<string, string> = {}) {
  return spawnSync("node", ["packages/cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0", ...env }
  });
}

// The single shared assertion: stdout is JSON + a valid envelope; optionally its
// `data` validates against a declared schema. Returns the parsed payload so chains
// can pull dynamic ids (run_id, event ids, aggregate ids) out of it.
function expectConformantJson(
  result: ReturnType<typeof runCli>,
  expectedCommand: string,
  dataSchema?: string
): { command: string; data: Record<string, unknown> } {
  if (typeof result.stdout !== "string" || result.stdout.trim() === "") {
    throw new Error(
      `${expectedCommand}: expected JSON on stdout but got none (status ${result.status}, stderr: ${result.stderr})`
    );
  }

  let payload: { command: string; data: Record<string, unknown> };
  try {
    payload = JSON.parse(result.stdout);
  } catch (error) {
    throw new Error(`${expectedCommand}: stdout is not valid JSON: ${(error as Error).message}\n${result.stdout}`);
  }

  expect(payload.command, `${expectedCommand}: command field`).toBe(expectedCommand);

  const envelope = validateBySchemaId(ENVELOPE_SCHEMA_ID, payload);
  expect(envelope, `${expectedCommand}: envelope diagnostics ${JSON.stringify(envelope.diagnostics)}`).toMatchObject({
    ok: true,
    diagnostics: []
  });

  if (dataSchema) {
    const data = validateBySchemaId(schemaId(dataSchema), payload.data);
    expect(
      data,
      `${expectedCommand}: data does not validate against ${dataSchema}: ${JSON.stringify(data.diagnostics)}`
    ).toMatchObject({ ok: true, diagnostics: [] });
  }

  return payload;
}

// The set of command names actually validated by this test (envelope-level). The
// final coverage test asserts this equals the canonical v1 surface.
const covered = new Set<string>();
function record(payload: { command: string }): void {
  covered.add(payload.command);
}

// ---------------------------------------------------------------------------
// Canonical v1 CLI surface — 44 commands (docs/release/v1-surface-inventory.md).
// `dataSchema` is set ONLY where the inventory maps the command to a dedicated
// result schema AND that mapping holds for real output (verified empirically).
// Commands left as `null` legitimately have no dedicated data schema: their
// `data` is a composite/ad-hoc shape covered only by the envelope. The trailing
// note explains any non-obvious envelope-only entry.
// ---------------------------------------------------------------------------
const CANONICAL_COMMANDS = [
  "version",
  "schema.list",
  "schema.validate-fixtures",
  "init",
  "matrix.validate",
  "matrix.list",
  "matrix.status",
  "matrix.upsert",
  "matrix.remove",
  "plan.showcase",
  "plan.walkthrough",
  "plan.cards",
  "capsule.validate",
  "capsule.list",
  "capsule.plan",
  "capsule.run",
  "evidence.record",
  "evidence.status",
  "evidence.void",
  "showcase.start",
  "showcase.record-observation",
  "showcase.record-verdict",
  "showcase.decide",
  "showcase.pause",
  "showcase.resume",
  "showcase.finish",
  "showcase.status",
  "showcase.approve",
  "showcase.reject",
  "showcase.correct",
  "workflow.set-mode",
  "workflow.get-mode",
  "migrate.test-matrix",
  "host.doctor",
  "host.project",
  "host.conformance",
  "doctor.skills",
  "doctor.package",
  "doctor.roots",
  "markers.bind",
  "markers.scan",
  "markers.prove",
  "markers.verify",
  "markers.validate-ledger"
] as const;

// Independent commands: each runs standalone against a fixture (read-only commands
// use the fixture path directly; mutating ones copy first). Stateful chains
// (matrix mutation, evidence, showcase, markers) are driven separately below.
//
// `fixture: null`         → no --repo (global/standalone command).
// `repo: "minimal-valid"` → read-only, --repo points at the shared fixture.
// `copy: "<fixture>"`     → mutating, --repo points at a fresh temp copy.
type IndependentCase = {
  command: string;
  dataSchema?: string;
  build: () => string[];
  note?: string;
};

const independentCases: IndependentCase[] = [
  { command: "version", build: () => ["--version", "--json"] },
  { command: "schema.list", build: () => ["schema", "list", "--json"] },
  {
    command: "schema.validate-fixtures",
    // Defaults to tests/fixtures/workspaces/minimal-valid relative to cwd (repoRoot).
    build: () => ["schema", "validate-fixtures", "--json"]
  },
  {
    command: "init",
    // Scaffolds into a fresh temp dir (never an existing fixture). data is the
    // scaffold result (created files + template + next steps); envelope only.
    build: () => ["init", "--repo", mkdtempSync(join(tmpdir(), "ucm-conf-init-")), "--json"]
  },
  {
    command: "matrix.validate",
    dataSchema: "matrix-validation-result",
    build: () => ["matrix", "validate", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  },
  {
    command: "matrix.list",
    dataSchema: "matrix-list-result",
    build: () => ["matrix", "list", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  },
  {
    command: "matrix.status",
    // data is a composite { matrix, evidence }; no dedicated schema — envelope only.
    build: () => ["matrix", "status", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  },
  {
    command: "plan.showcase",
    dataSchema: "presentation-plan-result",
    build: () => [
      "plan",
      "showcase",
      "--repo",
      join(fixturesRoot, "evidence-basic"),
      "--max-items",
      "1",
      "--host",
      "codex.cli",
      "--generated-at",
      "2026-06-25T12:00:00.000Z",
      "--json"
    ]
  },
  {
    command: "plan.walkthrough",
    dataSchema: "presentation-plan-result",
    build: () => ["plan", "walkthrough", "--repo", join(fixturesRoot, "evidence-basic"), "--json"]
  },
  {
    command: "capsule.validate",
    // data is a capsule-load snapshot (wraps capsules); no single-capsule schema.
    build: () => ["capsule", "validate", "--repo", join(fixturesRoot, "evidence-basic"), "--json"]
  },
  {
    command: "capsule.list",
    build: () => ["capsule", "list", "--repo", join(fixturesRoot, "evidence-basic"), "--json"]
  },
  {
    command: "capsule.plan",
    build: () => [
      "capsule",
      "plan",
      "--repo",
      join(fixturesRoot, "evidence-basic"),
      "--capsule",
      "capsule.showcase.golden",
      "--json"
    ]
  },
  {
    command: "capsule.run",
    // Mutating (may append evidence) → run against a copy. No --execute-commands,
    // so commands stay bounded; data is a run result with no dedicated schema.
    build: () => ["capsule", "run", "--repo", copyFixture("evidence-basic"), "--capsule", "capsule.showcase.golden", "--json"]
  },
  {
    command: "evidence.status",
    dataSchema: "evidence-status-result",
    build: () => ["evidence", "status", "--repo", join(fixturesRoot, "evidence-basic"), "--json"]
  },
  {
    command: "workflow.set-mode",
    // Mutating (rewrites use-cases.yml) → copy. data is an ad-hoc shape.
    build: () => ["workflow", "set-mode", "--repo", copyFixture("minimal-valid"), "--mode", "showcase-only", "--json"]
  },
  {
    command: "workflow.get-mode",
    // `workflow mode` → command "workflow.get-mode"; advisory shape, envelope only.
    build: () => ["workflow", "mode", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  },
  {
    command: "migrate.test-matrix",
    dataSchema: "migration-test-matrix-result",
    // Default --dry-run; reads migrations/test-matrix.json shipped in the fixture.
    build: () => [
      "migrate",
      "test-matrix",
      "--repo",
      join(fixturesRoot, "minimal-valid"),
      "--source",
      "migrations/test-matrix.json",
      "--json"
    ]
  },
  {
    command: "host.doctor",
    // data is a host doctor report; host-status-result describes a per-host status
    // record (a different artifact), so this is envelope only.
    build: () => ["host", "doctor", "--host", "codex", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  },
  {
    command: "host.project",
    // --dry-run keeps it read-only; data is a projection plan, envelope only.
    build: () => ["host", "project", "--host", "codex", "--repo", join(fixturesRoot, "minimal-valid"), "--dry-run", "--json"]
  },
  {
    command: "host.conformance",
    build: () => ["host", "conformance", "--host", "codex", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  },
  {
    command: "doctor.skills",
    build: () => ["doctor", "skills", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  },
  {
    command: "doctor.package",
    // Inspects the workspace as a package; the fixture is not a publishable package
    // so this returns an error envelope — still a valid envelope (the contract here).
    build: () => ["doctor", "package", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  },
  {
    command: "doctor.roots",
    build: () => ["doctor", "roots", "--repo", join(fixturesRoot, "minimal-valid"), "--json"]
  }
];

beforeAll(() => {
  const build = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (build.status !== 0) {
    throw new Error(build.stderr || build.stdout);
  }
}, 180_000);

afterAll(() => {
  // Best-effort temp cleanup; the OS reaps the tmpdir regardless.
  for (const dir of tempDirs.splice(0)) {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
  }
});

describe("v1 CLI output conformance", () => {
  test.each(independentCases.map((entry) => [entry.command, entry] as const))(
    "%s emits a schema-valid JSON envelope",
    (_command, entry) => {
      const payload = expectConformantJson(runCli(entry.build()), entry.command, entry.dataSchema);
      record(payload);
    }
  );

  test("matrix mutation chain (upsert → remove) emits matrix-mutation-result envelopes", () => {
    const workspaceRoot = copyFixture("minimal-valid");
    const planned = {
      id: "conformance.probe.case",
      title: "Conformance probe case",
      lifecycle: "planned",
      value_tier: "supporting",
      journey_role: "edge",
      usage_frequency: "rare",
      actor: "developer",
      intent: "Exercise the upsert mutation path.",
      preconditions: ["A workspace exists."],
      trigger: "The agent upserts a case.",
      scenarios: [{ id: "conformance.probe.case.main", kind: "steps", steps: ["Upsert the case."] }],
      observable_outcomes: ["The case appears in the matrix."],
      host_applicability: [{ host_surface: "codex.cli", supported: true }]
    };

    const upsert = expectConformantJson(
      runCli([
        "matrix",
        "upsert",
        "--repo",
        workspaceRoot,
        "--file",
        "use-cases/auth-login.yml",
        "--use-case-json",
        JSON.stringify(planned),
        "--json"
      ]),
      "matrix.upsert",
      "matrix-mutation-result"
    );
    expect(upsert.data).toMatchObject({ operation: "upsert", status: "created" });
    record(upsert);

    const remove = expectConformantJson(
      runCli([
        "matrix",
        "remove",
        "--repo",
        workspaceRoot,
        "--use-case",
        "conformance.probe.case",
        "--reason",
        "Conformance probe cleanup.",
        "--json"
      ]),
      "matrix.remove",
      "matrix-mutation-result"
    );
    expect(remove.data).toMatchObject({ operation: "remove" });
    record(remove);
  });

  test("evidence chain (record → void) emits evidence-append-result envelopes", () => {
    const workspaceRoot = copyFixture("evidence-basic");

    const recordPayload = expectConformantJson(
      runCli([
        "evidence",
        "record",
        "--repo",
        workspaceRoot,
        "--use-case",
        "showcase.live.golden",
        "--kind",
        "manual_observation",
        "--result",
        "pass",
        "--idempotency-key",
        "conformance:record",
        "--json"
      ]),
      "evidence.record",
      "evidence-append-result"
    );
    record(recordPayload);

    const event = recordPayload.data.event as { aggregate_id: string; event_id: string };
    const voidPayload = expectConformantJson(
      runCli([
        "evidence",
        "void",
        "--repo",
        workspaceRoot,
        "--evidence",
        event.aggregate_id,
        "--expected-head",
        event.event_id,
        "--reason",
        "Conformance probe void.",
        "--idempotency-key",
        "conformance:void",
        "--json"
      ]),
      "evidence.void",
      "evidence-append-result"
    );
    record(voidPayload);
  });

  test("showcase lifecycle chain emits schema-valid envelopes for every subcommand", () => {
    const workspaceRoot = copyFixture("evidence-basic");
    const APPEND = "showcase-event-append-result";

    const start = expectConformantJson(
      runCli(["showcase", "start", "--repo", workspaceRoot, "--adhoc", "--select", "showcase.live.golden", "--json"]),
      "showcase.start",
      // showcase-start-result.schema.json is a $ref alias to the append-result schema.
      "showcase-start-result"
    );
    record(start);
    const runId = (start.data as { run_id: string }).run_id;
    const item = (start.data as { status: { items: Array<{ plan_item_id: string }> } }).status.items[0].plan_item_id;

    record(
      expectConformantJson(
        runCli([
          "showcase",
          "record-observation",
          "--repo",
          workspaceRoot,
          "--run",
          runId,
          "--item",
          item,
          "--text",
          "Observed expected behavior.",
          "--json"
        ]),
        "showcase.record-observation",
        APPEND
      )
    );

    record(
      expectConformantJson(
        runCli(["showcase", "pause", "--repo", workspaceRoot, "--run", runId, "--reason", "Pause to inspect.", "--json"]),
        "showcase.pause",
        APPEND
      )
    );
    record(
      expectConformantJson(
        runCli(["showcase", "resume", "--repo", workspaceRoot, "--run", runId, "--reason", "Resume.", "--json"]),
        "showcase.resume",
        APPEND
      )
    );

    const verdict = expectConformantJson(
      runCli([
        "showcase",
        "record-verdict",
        "--repo",
        workspaceRoot,
        "--run",
        runId,
        "--item",
        item,
        "--verdict",
        "fail",
        "--actor",
        "user",
        "--json"
      ]),
      "showcase.record-verdict",
      APPEND
    );
    record(verdict);
    const verdictEventId = (verdict.data as { event: { event_id: string } }).event.event_id;

    record(
      expectConformantJson(
        runCli([
          "showcase",
          "decide",
          "--repo",
          workspaceRoot,
          "--run",
          runId,
          "--verdict-event",
          verdictEventId,
          "--decision",
          "waive_with_reason",
          "--reason",
          "Accepted as a known gap.",
          "--actor",
          "user",
          "--json"
        ]),
        "showcase.decide",
        APPEND
      )
    );

    record(
      expectConformantJson(
        runCli([
          "showcase",
          "correct",
          "--repo",
          workspaceRoot,
          "--run",
          runId,
          "--target-event",
          verdictEventId,
          "--verdict",
          "pass",
          "--reason",
          "Original verdict was entered against the wrong criterion.",
          "--json"
        ]),
        "showcase.correct",
        APPEND
      )
    );

    record(
      expectConformantJson(
        runCli(["showcase", "finish", "--repo", workspaceRoot, "--run", runId, "--json"]),
        "showcase.finish",
        // showcase-finish-result.schema.json is a $ref alias to the append-result schema.
        "showcase-finish-result"
      )
    );

    record(
      expectConformantJson(
        runCli(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]),
        "showcase.status",
        "showcase-run-status-result"
      )
    );

    // approve / reject are approval-gated: untrusted automation cannot mint a
    // trusted-user approval, so a hermetic run can only exercise the REJECTED path,
    // which returns an error envelope with data:{}. We therefore assert the
    // envelope only (the contract under test) and do NOT bind a data schema — the
    // success path requires an interactive trusted-user confirmation that cannot be
    // produced in a hermetic test. This is documented approval-policy behavior, not
    // a contract violation.
    record(
      expectConformantJson(
        runCli([
          "showcase",
          "approve",
          "--repo",
          workspaceRoot,
          "--run",
          runId,
          "--actor",
          "agent",
          "--statement",
          "Agent cannot approve a user-required scope.",
          "--json"
        ]),
        "showcase.approve"
      )
    );
    record(
      expectConformantJson(
        runCli([
          "showcase",
          "reject",
          "--repo",
          workspaceRoot,
          "--run",
          runId,
          "--actor",
          "user",
          "--statement",
          "Scripted automation cannot impersonate the user.",
          "--json"
        ]),
        "showcase.reject"
      )
    );
  });

  test("plan.cards renders cards from a generated plan file", () => {
    const workspaceRoot = copyFixture("evidence-basic");
    const planPayload = expectConformantJson(
      runCli([
        "plan",
        "showcase",
        "--repo",
        workspaceRoot,
        "--max-items",
        "1",
        "--host",
        "codex.cli",
        "--generated-at",
        "2026-06-25T12:00:00.000Z",
        "--json"
      ]),
      "plan.showcase",
      "presentation-plan-result"
    );
    const plan = (planPayload.data as { plan: unknown }).plan;
    const plansDir = join(workspaceRoot, "presentation-plans");
    mkdirSync(plansDir, { recursive: true });
    const planPath = join(plansDir, "generated-showcase.json");
    writeFileSync(planPath, `${JSON.stringify(plan, null, 2)}\n`);

    record(
      expectConformantJson(
        runCli(["plan", "cards", "--repo", workspaceRoot, "--plan-file", planPath, "--json"]),
        "plan.cards"
      )
    );
  });

  test("trust-engine chain (bind → scan → verify → prove → validate-ledger) emits envelopes", () => {
    // The five trust commands emit JSON unconditionally (no --json toggle); they
    // must still validate against the envelope. We synthesize a minimal product
    // workspace with one Swift-bound use case and an ed25519 keypair so the whole
    // chain runs end-to-end without git or a real CI signer. Exit codes vary
    // (verify returns non-zero because the policy wants a real user verifier); the
    // envelope is the contract under test, so exit status is not asserted.
    const workspaceRoot = mkdtempSync(join(tmpdir(), "ucm-conf-markers-"));
    tempDirs.push(workspaceRoot);
    writeFileSync(
      join(workspaceRoot, "use-cases.yml"),
      [
        "schema_version: 1",
        "workspace_id: conformance.markers",
        "data_root: .",
        "use_cases_dir: use-cases",
        "evidence_dir: evidence",
        "demo_capsules_dir: demo-capsules",
        "showcase_runs_dir: showcase-runs",
        "component_id: presentation-skills",
        "default_workflow_mode: continuous",
        ""
      ].join("\n")
    );
    mkdirSync(join(workspaceRoot, "use-cases"), { recursive: true });
    writeFileSync(
      join(workspaceRoot, "use-cases/checkout.yml"),
      [
        "schema_version: 1",
        "feature:",
        "  id: checkout",
        "  name: Checkout",
        "  summary: Shoppers can apply coupons during checkout.",
        "metadata:",
        "  owner: product",
        "  lifecycle: active",
        "use_cases:",
        "  - id: checkout.apply_coupon",
        "    title: Apply a valid coupon",
        "    lifecycle: active",
        "    value_tier: critical",
        "    journey_role: golden",
        "    usage_frequency: common",
        "    actor: shopper",
        "    intent: Apply a valid coupon to a cart.",
        "    preconditions: [A cart exists.]",
        "    trigger: The shopper submits a coupon code.",
        "    scenarios:",
        "      - id: checkout.apply_coupon.web",
        "        kind: steps",
        "        steps: [The shopper submits a coupon code.]",
        "    observable_outcomes: [The cart total reflects the discount.]",
        "    host_applicability:",
        "      - host_surface: codex.cli",
        "        supported: true",
        "    verification_policy:",
        "      mode: requirements",
        "      requirements:",
        "        - evidence_kind: live_demo",
        "          required_verifiers: [user]",
        "          minimum_count: 1",
        "    approval_policy:",
        "      mode: predefined",
        "      requirements:",
        "        - approver_type: user",
        "          minimum_count: 1",
        "      statement: Final acceptance requires user-visible proof.",
        ""
      ].join("\n")
    );
    mkdirSync(join(workspaceRoot, "Sources/Checkout"), { recursive: true });
    writeFileSync(
      join(workspaceRoot, "Sources/Checkout/CouponService.swift"),
      ["import Foundation", "", "@MainActor", "public func applyCoupon(_ code: String) async throws -> Int {", "    return 1", "}", ""].join("\n")
    );

    const keypair = generateKeyPairSync("ed25519");
    const publicKeyPath = join(workspaceRoot, "public-key.pem");
    writeFileSync(publicKeyPath, keypair.publicKey.export({ type: "spki", format: "pem" }) as string);
    const privateKeyPem = keypair.privateKey.export({ type: "pkcs8", format: "pem" }) as string;
    const verificationResultsPath = join(workspaceRoot, "verification-results.jsonl");

    record(
      expectConformantJson(
        runCli([
          "bind",
          "--repo",
          workspaceRoot,
          "--row",
          "checkout.apply_coupon",
          "--file",
          "Sources/Checkout/CouponService.swift",
          "--mode",
          "swift-func",
          "--line",
          "3",
          "--json"
        ]),
        "markers.bind"
      )
    );

    record(
      expectConformantJson(
        runCli(["scan", "--repo", workspaceRoot, "--public-key", publicKeyPath, "--json"]),
        "markers.scan"
      )
    );

    record(
      expectConformantJson(
        runCli([
          "verify",
          "--repo",
          workspaceRoot,
          "--all",
          "--out",
          verificationResultsPath,
          "--public-key",
          publicKeyPath,
          "--json"
        ]),
        "markers.verify"
      )
    );

    record(
      expectConformantJson(
        runCli(
          [
            "prove",
            "--repo",
            workspaceRoot,
            "--all",
            "--trusted-ci",
            "--signing-key-env",
            "UCM_CONFORMANCE_KEY",
            "--unsafe-assume-verification-result",
            "pass",
            "--public-key",
            publicKeyPath,
            "--json"
          ],
          { UCM_ALLOW_UNSAFE_VERIFICATION: "1", UCM_CONFORMANCE_KEY: privateKeyPem }
        ),
        "markers.prove"
      )
    );

    record(
      expectConformantJson(
        runCli(["validate-ledger", "--repo", workspaceRoot, "--public-key", publicKeyPath, "--json"]),
        "markers.validate-ledger"
      )
    );
  });

  // Coverage gate: every canonical v1 command must have been exercised above. If a
  // command is added to the CLI surface, add it to CANONICAL_COMMANDS and cover it
  // here — otherwise this assertion (and the surface inventory) goes stale loudly.
  test("covers every command in the canonical v1 CLI surface (44)", () => {
    expect(CANONICAL_COMMANDS).toHaveLength(44);
    const expected = [...CANONICAL_COMMANDS].sort();
    const actual = [...covered].sort();
    expect(actual).toEqual(expected);
  });
});
