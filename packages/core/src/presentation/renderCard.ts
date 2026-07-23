import { defaultFormatForDeliveryKind, FORMAT_META, type PresentationFormat } from "./presentationFormat.js";
import type { PresentationPlanItem } from "./types.js";

/**
 * A recorded outcome for an item, supplied at render time. Absent => the
 * prepared / open card (no live claim). All non-ASCII glyphs in this module are
 * written as `\u` escapes so the canonical emoji stay solely in FORMAT_META.
 */
export type RenderResult = {
  /** A live status. Only Testing / Comparing may carry one. */
  status?: "pass" | "fail";
  /** What was actually observed. */
  got?: string;
  /** The recorded evidence id backing a `pass`. A pass checkmark requires this. */
  evidenceId?: string;
  /** True only when a human answered an "Over to you" prompt. */
  answeredByHuman?: boolean;
};

/** Thrown when a render would let the header verb lie. */
export class HonestyRuleError extends Error {
  constructor(
    message: string,
    readonly code: string
  ) {
    super(message);
    this.name = "HonestyRuleError";
  }
}

const MARK_PASS = "\u2713"; // check mark
const MARK_FAIL = "\u2717"; // ballot x
const DOT = "\u00b7"; // middle dot

/**
 * Render the fixed, scannable card for a plan item. Pure and deterministic.
 * Enforces the render-time honesty rule: the emoji + verb is a promise that
 * cannot be broken (a failed live test cannot become an explanation; a `pass`
 * checkmark needs real recorded evidence; an "Over to you" prompt can only be
 * answered by a human).
 *
 * Trust boundary: this is a pure function over the supplied `result`. It cannot
 * see a result that the caller withholds (a recorded live failure rendered with
 * no result reads as pending), and it trusts `answeredByHuman` as supplied. The
 * upstream guarantee -- that a result/answer is bound to a real recorded,
 * human-origin run event -- is enforced by the evidence/showcase ledger and the
 * deferred per-claim evidence-verifier contract (see the spec), not here.
 */
export function renderCard(item: PresentationPlanItem, result?: RenderResult): string {
  // Defensive: external plan files may omit the field even though selection
  // always emits it. Fall back to the delivery_kind projection rather than
  // indexing FORMAT_META with undefined.
  const format = item.presentation_format ?? defaultFormatForDeliveryKind(item.delivery_kind);
  enforceHonesty(item, format, result);
  const meta = FORMAT_META[format];
  // Markdown card heading: emoji + verb as a ### title, item id + descriptor
  // beneath it, so hosts that render markdown show a scannable card and plain-
  // text hosts still read naturally top-to-bottom.
  const header = `### ${meta.emoji} ${meta.verb}: ${item.use_case_id}\n\n\`${item.use_case_id}\` ${DOT} ${meta.descriptor}`;
  return `${header}\n\n${renderBody(item, format, result)}`;
}

function enforceHonesty(
  item: PresentationPlanItem,
  format: PresentationFormat,
  result: RenderResult | undefined
): void {
  if (!result) {
    return;
  }
  // A non-live narrated format cannot re-render a live pass/fail result.
  if (format !== "testing" && format !== "comparing" && format !== "user_led" && result.status) {
    throw new HonestyRuleError(
      `A live result cannot be re-rendered under the ${FORMAT_META[format].verb} format.`,
      "live_result_not_renderable"
    );
  }
  // Over to you can only be answered by a human-origin event.
  if (format === "user_led" && result.answeredByHuman !== true) {
    throw new HonestyRuleError(
      "Over to you stays open until a human answers; an agent cannot fill it.",
      "user_led_requires_human_answer"
    );
  }
  // A pass checkmark must correspond to a real recorded result: the evidence id
  // must be present AND a member of the item's active evidence. With no recorded
  // evidence a pass cannot be claimed (no escape hatch for the unrecorded case).
  if ((format === "testing" || format === "comparing") && result.status === "pass") {
    const active = item.evidence_summary?.active_evidence_ids ?? [];
    const backed = Boolean(result.evidenceId) && active.includes(result.evidenceId!);
    if (!backed) {
      throw new HonestyRuleError(
        "A pass checkmark requires a real recorded result, never agent prose alone.",
        "pass_requires_recorded_evidence"
      );
    }
  }
}

function renderBody(
  item: PresentationPlanItem,
  format: PresentationFormat,
  result: RenderResult | undefined
): string {
  switch (format) {
    case "testing":
      return renderTesting(item, result);
    case "comparing":
      return renderComparing(item, result);
    case "inspecting":
      return renderInspecting(item);
    case "reviewing":
      return renderReviewing(item);
    case "user_led":
      return renderUserLed(item, result);
    case "explaining":
      return renderExplaining(item);
  }
}

function renderTesting(item: PresentationPlanItem, result: RenderResult | undefined): string {
  const steps =
    item.resolved_steps.length > 0
      ? item.resolved_steps.map((step, index) => `${index + 1}. ${step}`)
      : ["1. (none)"];
  return [
    "**Steps**",
    ...steps,
    "",
    "**Expect**",
    joinSteps(item.expected_observations),
    "",
    "**Actual**",
    gotLine(result)
  ].join("\n");
}

function renderComparing(item: PresentationPlanItem, result: RenderResult | undefined): string {
  const bad = item.resolved_steps[0] ?? "(blocked case)";
  const good = item.resolved_steps[1] ?? "(allowed case)";
  const suffix = result?.got ? `    -> ${result.got}` : "";
  return [
    `${MARK_FAIL}  ${bad}    -> should be blocked${suffix}`,
    `${MARK_PASS}  ${good}    -> should work${suffix}`
  ].join("\n");
}

function renderInspecting(item: PresentationPlanItem): string {
  return [
    `In:    ${item.resolved_steps[0] ?? "(the real artifact)"}`,
    `Look:  ${item.expected_observations[0] ?? "(the part that matters)"}`
  ].join("\n");
}

function renderReviewing(item: PresentationPlanItem): string {
  const from = item.evidence_summary?.basis ?? "(earlier run)";
  return [
    `From:   ${from}`,
    `Shows:  ${joinSteps(item.expected_observations)}    (not re-run now)`
  ].join("\n");
}

function renderUserLed(item: PresentationPlanItem, result: RenderResult | undefined): string {
  const steps =
    item.resolved_steps.length > 0
      ? item.resolved_steps.map((step, index) => `${index + 1}.  ${step}`)
      : ["1.  (follow the steps with the agent)"];
  const confirm = result?.answeredByHuman === true ? "Confirm:  yes" : "Confirm:  yes / no";
  return `${steps.join("\n")}\n\n${confirm}`;
}

function renderExplaining(item: PresentationPlanItem): string {
  const text =
    item.expected_observations.length > 0
      ? joinSteps(item.expected_observations)
      : joinSteps(item.resolved_steps);
  return `${text}\n\n(not run -- explanation only)`;
}

function gotLine(result: RenderResult | undefined): string {
  if (!result || !result.status) {
    return "(pending)";
  }
  const mark = result.status === "pass" ? MARK_PASS : MARK_FAIL;
  return `${result.got ?? ""} ${mark}`.trim();
}

function joinSteps(values: readonly string[]): string {
  return values.length > 0 ? values.join("; ") : "(none)";
}
