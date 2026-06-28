import { describe, expect, test } from "vitest";
import { FORMAT_META, type PresentationFormat } from "../../src/presentation/presentationFormat.js";
import { HonestyRuleError, renderCard } from "../../src/presentation/renderCard.js";
import type { PresentationPlanItem } from "../../src/presentation/types.js";

const MARK_PASS = "✓";
const MARK_FAIL = "✗";

function makeItem(overrides: Partial<PresentationPlanItem> = {}): PresentationPlanItem {
  return {
    plan_item_id: "item.demo.feature",
    presentation_format: "testing",
    delivery_kind: "live_demo",
    scenario_scope: "whole_use_case",
    use_case_id: "demo.feature",
    scenario_ids: [],
    use_case_content_hash: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    estimated_seconds: 60,
    estimate_source: "default_profile",
    setup_steps: [],
    resolved_steps: ["Run the demo command.", "Run the second command."],
    expected_observations: ["The success banner appears."],
    teardown_steps: [],
    required_permissions: [],
    safety_constraints: [],
    verification_policy_snapshot: { mode: "none" },
    approval_policy_snapshot: { mode: "none" },
    approval_resolution_required_at_run_start: false,
    required_evidence: [],
    evidence_summary: { readiness: "missing", active_evidence_ids: [], basis: "no_active_evidence" },
    freshness_summary: { state: "unknown", basis: "missing_evidence" },
    known_gaps: [],
    selection_reasons: ["demo"],
    selection_reason_codes: ["demo"],
    score_components: {},
    ...overrides
  };
}

describe("renderCard", () => {
  test("renders each of the six formats with its exact emoji+verb header and body slots", () => {
    const formats: PresentationFormat[] = [
      "testing",
      "comparing",
      "inspecting",
      "reviewing",
      "user_led",
      "explaining"
    ];
    for (const format of formats) {
      const meta = FORMAT_META[format];
      const card = renderCard(makeItem({ presentation_format: format }));
      expect(card).toContain(`${meta.emoji} ${meta.verb}:`);
      expect(card).toContain("demo.feature");
      expect(card).toContain(meta.descriptor);
    }

    const testing = renderCard(makeItem({ presentation_format: "testing" }));
    expect(testing).toContain("Run:");
    expect(testing).toContain("Expect:");
    expect(testing).toContain("Got:");

    const comparing = renderCard(makeItem({ presentation_format: "comparing" }));
    expect(comparing).toContain(MARK_FAIL);
    expect(comparing).toContain(MARK_PASS);

    const inspecting = renderCard(makeItem({ presentation_format: "inspecting" }));
    expect(inspecting).toContain("In:");
    expect(inspecting).toContain("Look:");

    const reviewing = renderCard(makeItem({ presentation_format: "reviewing" }));
    expect(reviewing).toContain("From:");
    expect(reviewing).toContain("Shows:");

    const userLed = renderCard(makeItem({ presentation_format: "user_led" }));
    expect(userLed).toContain("1.");
    expect(userLed).toContain("Confirm:  yes / no");

    const explaining = renderCard(makeItem({ presentation_format: "explaining" }));
    expect(explaining).toContain("explanation only");
    expect(explaining).toContain("not run");
  });

  test("Testing pass requires real evidence; pending has no checkmark", () => {
    const item = makeItem({
      presentation_format: "testing",
      evidence_summary: { readiness: "available_current", active_evidence_ids: ["ev.1"], basis: "ok" }
    });

    expect(() => renderCard(item, { status: "pass", got: "Banner shown" })).toThrow(HonestyRuleError);

    const withEvidence = renderCard(item, { status: "pass", got: "Banner shown", evidenceId: "ev.1" });
    expect(withEvidence).toContain(`Got:`);
    expect(withEvidence).toContain(MARK_PASS);

    const pending = renderCard(item);
    expect(pending).not.toContain(MARK_PASS);
    expect(pending).toContain("(pending)");
  });

  test("a pass with no recorded evidence cannot earn a checkmark, even with a fabricated id", () => {
    // Default item has active_evidence_ids: [] -- nothing recorded. A made-up
    // evidence id must NOT satisfy the pass check (closes the empty-active hole).
    const unrecorded = makeItem({ presentation_format: "testing" });
    expect(unrecorded.evidence_summary?.active_evidence_ids).toEqual([]);
    expect(() => renderCard(unrecorded, { status: "pass", got: "x", evidenceId: "fabricated" })).toThrow(
      HonestyRuleError
    );
  });

  test("Testing fail renders cross; the same live result cannot be re-rendered as Explaining", () => {
    const testing = makeItem({ presentation_format: "testing" });
    const failed = renderCard(testing, { status: "fail", got: "Banner missing" });
    expect(failed).toContain("Banner missing");
    expect(failed).toContain(MARK_FAIL);

    const explaining = makeItem({ presentation_format: "explaining" });
    expect(() => renderCard(explaining, { status: "fail", got: "Banner missing" })).toThrow(HonestyRuleError);
  });

  test("Over to you stays open unless a human answered; an agent answer cannot fill it", () => {
    const item = makeItem({ presentation_format: "user_led" });

    const open = renderCard(item);
    expect(open).toContain("Confirm:  yes / no");

    expect(() => renderCard(item, { answeredByHuman: false })).toThrow(HonestyRuleError);

    const answered = renderCard(item, { answeredByHuman: true });
    expect(answered).toContain("Confirm:  yes");
    expect(answered).not.toContain("Confirm:  yes / no");
  });
});
