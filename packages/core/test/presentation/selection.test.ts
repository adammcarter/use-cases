import { cpSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../src/schema/index.js";
import { resolveWorkspaceContext } from "../../src/roots.js";
import { loadUseCaseMatrix } from "../../src/useCases/loadUseCaseMatrix.js";
import { appendEvidenceEvent, replayEvidence } from "../../src/evidence/index.js";
import {
  computePresentationPlanHash,
  formatToDeliveryKind,
  selectShowcasePlan,
  selectWalkthroughPlan
} from "../../src/presentation/index.js";

const PRESENTATION_FORMATS = [
  "testing",
  "comparing",
  "inspecting",
  "reviewing",
  "user_led",
  "explaining"
];

const repoRoot = resolve(import.meta.dirname, "../../../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

describe("P5 presentation plan selection", () => {
  test("showcase plans prefer changed critical golden paths over fresh long-tail evidence", () => {
    const workspaceRoot = fixtureWorkspace("presentation-selection");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const matrix = loadUseCaseMatrix({ context });
    appendFreshEvidenceFor(workspaceRoot, "settings.theme.rare", "test_result");
    const evidence = replayEvidence({ context });

    const result = selectShowcasePlan({
      context,
      matrix,
      evidence,
      request: {
        audience: "reviewer",
        timeboxSeconds: 360,
        maxItems: 2,
        hostSurface: "codex.cli",
        changedPaths: ["src/checkout/flow.ts"],
        generatedAt: "2026-06-25T12:00:00.000Z"
      }
    });

    expect(result).toMatchObject({
      schema_version: 1,
      outcome: "generated",
      candidate_summary: {
        considered: 7,
        selected: 2
      },
      input_integrity: {
        matrix: "clean",
        evidence: "clean"
      }
    });
    expect(
      validateBySchemaId(
        "https://use-cases.dev/schemas/v1/presentation-plan-result.schema.json",
        result
      )
    ).toMatchObject({ ok: true, diagnostics: [] });
    expect(result.plan).toMatchObject({
      schema_version: 1,
      mode: "showcase",
      complete: true,
      readiness: "ready_with_evidence_gaps",
      prepared_not_performed: true,
      integrity_acknowledgement_required: false,
      selection_method: "deterministic"
    });
    expect(
      validateBySchemaId(
        "https://use-cases.dev/schemas/v1/presentation-plan.schema.json",
        result.plan
      )
    ).toMatchObject({ ok: true, diagnostics: [] });

    const selectedIds = result.plan?.selected_items.map((item) => item.use_case_id);
    expect(selectedIds?.[0]).toBe("checkout.purchase.golden");
    expect(selectedIds).not.toContain("settings.theme.rare");
    expect(result.plan?.selected_items.every((item) => item.delivery_kind === "live_demo")).toBe(true);
    expect(
      result.plan?.selected_items.every((item) => PRESENTATION_FORMATS.includes(item.presentation_format))
    ).toBe(true);
    expect(
      result.plan?.selected_items.find((item) => item.use_case_id === "checkout.purchase.golden")
    ).toMatchObject({
      presentation_format: "user_led",
      delivery_kind: "live_demo"
    });
    expect(
      result.plan?.selected_items.every(
        (item) => formatToDeliveryKind(item.presentation_format, item.delivery_kind) === item.delivery_kind
      )
    ).toBe(true);
    expect(result.plan?.selected_items.every((item) => item.selection_reasons.length > 0)).toBe(true);
    expect(result.plan?.selected_items.every((item) => item.selection_reason_codes.length > 0)).toBe(true);
    expect(result.plan?.selected_items.every((item) => item.plan_item_id.startsWith("item."))).toBe(true);
    expect(result.plan?.selected_items.every((item) => item.evidence_summary.readiness.length > 0)).toBe(true);
    expect(result.plan?.selected_items.every((item) => item.required_evidence.length > 0)).toBe(true);
    expect(result.plan?.selected_items.every((item) => item.known_gaps.length > 0)).toBe(true);
    expect(
      result.plan?.sections.flatMap((section) => section.item_ids).sort()
    ).toEqual(result.plan?.selected_items.map((item) => item.plan_item_id).sort());
    expect(result.plan?.selected_items.find((item) => item.use_case_id === "checkout.purchase.golden")).toMatchObject({
      approval_resolution_required_at_run_start: true
    });
    expect(result.plan?.exclusions).toContainEqual(
      expect.objectContaining({
        use_case_id: "checkout.validation.edge",
        reason_code: "max_items"
      })
    );
    expect(JSON.stringify(result.plan)).not.toContain("verification_satisfied");
    expect(JSON.stringify(result.plan)).not.toContain("user_signed_off");
    expect(JSON.stringify(result.plan)).not.toContain("release_ready");
  });

  test("walkthrough plans include alternate, edge, negative, and failure coverage when available", () => {
    const workspaceRoot = fixtureWorkspace("presentation-selection");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const result = selectWalkthroughPlan({
      context,
      matrix: loadUseCaseMatrix({ context }),
      evidence: replayEvidence({ context }),
      request: {
        audience: "reviewer",
        timeboxSeconds: 1800,
        maxItems: 8,
        hostSurface: "codex.cli",
        generatedAt: "2026-06-25T12:00:00.000Z"
      }
    });

    expect(result.outcome).toBe("generated");
    expect(result.plan?.mode).toBe("walkthrough");
    expect(result.plan?.selected_items.map((item) => item.use_case_id)).toEqual(
      expect.arrayContaining([
        "checkout.cart.alternate",
        "checkout.validation.edge",
        "checkout.payment.negative",
        "checkout.inventory.failure"
      ])
    );
    expect(result.plan?.sections.map((section) => section.section_id)).toEqual([
      "section.primary-path",
      "section.coverage"
    ]);
  });

  test("requested use cases override default showcase score ordering", () => {
    const workspaceRoot = fixtureWorkspace("presentation-selection");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const result = selectShowcasePlan({
      context,
      matrix: loadUseCaseMatrix({ context }),
      evidence: replayEvidence({ context }),
      request: {
        audience: "reviewer",
        timeboxSeconds: 600,
        maxItems: 2,
        hostSurface: "codex.cli",
        requestedUseCaseIds: ["settings.theme.rare"],
        generatedAt: "2026-06-25T12:00:00.000Z"
      }
    });

    expect(result.outcome).toBe("generated");
    expect(result.plan?.selected_items.map((item) => item.use_case_id)).toEqual(["settings.theme.rare"]);
    expect(result.plan?.exclusions).toContainEqual(
      expect.objectContaining({
        use_case_id: "checkout.purchase.golden",
        reason_code: "not_requested"
      })
    );
  });

  test("plan content hash ignores volatile IDs and timestamps but changes with order", () => {
    const workspaceRoot = fixtureWorkspace("presentation-selection");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const base = selectShowcasePlan({
      context,
      matrix: loadUseCaseMatrix({ context }),
      evidence: replayEvidence({ context }),
      request: {
        audience: "reviewer",
        timeboxSeconds: 600,
        maxItems: 3,
        hostSurface: "codex.cli",
        generatedAt: "2026-06-25T12:00:00.000Z",
        freshnessEvaluatedAt: "2026-06-25T12:00:00.000Z"
      }
    }).plan;
    const later = selectShowcasePlan({
      context,
      matrix: loadUseCaseMatrix({ context }),
      evidence: replayEvidence({ context }),
      request: {
        audience: "reviewer",
        timeboxSeconds: 600,
        maxItems: 3,
        hostSurface: "codex.cli",
        generatedAt: "2026-06-25T12:05:00.000Z",
        freshnessEvaluatedAt: "2026-06-25T12:00:00.000Z"
      }
    }).plan;
    if (!base || !later) {
      throw new Error("expected generated plans");
    }

    expect(later.plan_id).not.toBe(base.plan_id);
    expect(later.plan_content_hash).toBe(base.plan_content_hash);

    const reordered = {
      ...base,
      selected_items: base.selected_items.slice().reverse()
    };
    expect(computePresentationPlanHash(reordered)).not.toBe(base.plan_content_hash);
  });

  test("clean input with no eligible items returns no plan without treating it as input damage", () => {
    const workspaceRoot = fixtureWorkspace("presentation-no-eligible");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const result = selectShowcasePlan({
      context,
      matrix: loadUseCaseMatrix({ context }),
      evidence: replayEvidence({ context }),
      request: {
        audience: "reviewer",
        timeboxSeconds: 600,
        maxItems: 3,
        hostSurface: "codex.cli",
        generatedAt: "2026-06-25T12:00:00.000Z"
      }
    });

    expect(result).toMatchObject({
      schema_version: 1,
      outcome: "no_eligible_items",
      plan: null,
      input_integrity: {
        matrix: "clean",
        evidence: "clean"
      },
      candidate_summary: {
        eligible: 0,
        selected: 0
      }
    });
  });

  test("partial input produces an explicit partial plan only when tolerant generation is requested", () => {
    const workspaceRoot = fixtureWorkspace("presentation-partial");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const matrix = loadUseCaseMatrix({ context });
    const evidence = replayEvidence({ context });
    const request = {
      audience: "reviewer",
      timeboxSeconds: 600,
      maxItems: 3,
      hostSurface: "codex.cli" as const,
      generatedAt: "2026-06-25T12:00:00.000Z"
    };

    const strict = selectShowcasePlan({ context, matrix, evidence, request: { ...request, strict: true } });
    expect(strict).toMatchObject({
      outcome: "integrity_blocked",
      plan: null,
      input_integrity: {
        matrix: "partial"
      }
    });

    const tolerant = selectShowcasePlan({ context, matrix, evidence, request });
    expect(tolerant).toMatchObject({
      outcome: "generated",
      plan: {
        complete: false,
        readiness: "partial_due_to_integrity",
        integrity_acknowledgement_required: true,
        prepared_not_performed: true
      }
    });
  });
});

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-case-matrix-${name}-`));
  cpSync(join(fixturesRoot, name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function appendFreshEvidenceFor(workspaceRoot: string, useCaseId: string, kind: "test_result" | "live_demo"): void {
  const context = resolveWorkspaceContext({ workspaceRoot });
  const matrix = loadUseCaseMatrix({ context });
  const resolved = matrix.resolveUseCase(useCaseId);
  if (resolved.kind !== "resolved") {
    throw new Error(`fixture use case ${useCaseId} did not resolve`);
  }
  appendEvidenceEvent({
    context,
    idempotencyKey: `presentation-test:${useCaseId}:${kind}`,
    target: {
      use_case_id: useCaseId,
      use_case_semantic_hash: resolved.useCase.semanticHash
    },
    kind,
    result: "pass",
    summary: `Fresh ${kind} evidence for ${useCaseId}.`,
    actorType: "script",
    hostSurface: "codex.cli"
  });
}
