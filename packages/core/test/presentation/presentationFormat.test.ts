import { describe, expect, test } from "vitest";
import {
  FORMAT_META,
  choosePresentationFormat,
  defaultFormatForDeliveryKind,
  formatToDeliveryKind,
  type PresentationFormat
} from "../../src/presentation/presentationFormat.js";

const ALL_FORMATS: PresentationFormat[] = [
  "testing",
  "comparing",
  "inspecting",
  "reviewing",
  "user_led",
  "explaining"
];

describe("PresentationFormat catalog", () => {
  test("FORMAT_META has all six formats with exact emoji, verb, descriptor, and actor", () => {
    expect(Object.keys(FORMAT_META).sort()).toEqual([...ALL_FORMATS].sort());

    expect(FORMAT_META.testing.emoji).toBe("\u{1F9EA}");
    expect(FORMAT_META.comparing.emoji).toBe("⚖️");
    expect(FORMAT_META.inspecting.emoji).toBe("\u{1F50E}");
    expect(FORMAT_META.reviewing.emoji).toBe("\u{1F4DC}");
    expect(FORMAT_META.user_led.emoji).toBe("\u{1F64B}");
    expect(FORMAT_META.explaining.emoji).toBe("\u{1F4AC}");

    for (const format of ALL_FORMATS) {
      const meta = FORMAT_META[format];
      expect(meta.verb.length).toBeGreaterThan(0);
      expect(meta.descriptor.length).toBeGreaterThan(0);
    }

    expect(FORMAT_META.user_led.actor).toBe("user");
    for (const format of ALL_FORMATS.filter((value) => value !== "user_led")) {
      expect(FORMAT_META[format].actor).toBe("agent");
    }
  });

  test("formatToDeliveryKind maps live, evidence, explanation, and user_led fallback", () => {
    expect(formatToDeliveryKind("testing", "explanation")).toBe("live_demo");
    expect(formatToDeliveryKind("comparing", "explanation")).toBe("live_demo");
    expect(formatToDeliveryKind("inspecting", "live_demo")).toBe("evidence_review");
    expect(formatToDeliveryKind("reviewing", "live_demo")).toBe("evidence_review");
    expect(formatToDeliveryKind("explaining", "live_demo")).toBe("explanation");
    expect(formatToDeliveryKind("user_led", "live_demo")).toBe("live_demo");
    expect(formatToDeliveryKind("user_led", "evidence_review")).toBe("evidence_review");
    expect(formatToDeliveryKind("user_led", "explanation")).toBe("explanation");
  });

  test("defaultFormatForDeliveryKind maps each delivery kind to its default format", () => {
    expect(defaultFormatForDeliveryKind("live_demo")).toBe("testing");
    expect(defaultFormatForDeliveryKind("evidence_review")).toBe("reviewing");
    expect(defaultFormatForDeliveryKind("explanation")).toBe("explaining");
  });

  test("choosePresentationFormat prioritises user, then contrast, then default", () => {
    expect(choosePresentationFormat({ baseDeliveryKind: "live_demo", needsUser: true })).toBe("user_led");
    expect(
      choosePresentationFormat({ baseDeliveryKind: "live_demo", needsUser: true, isContrast: true })
    ).toBe("user_led");
    expect(choosePresentationFormat({ baseDeliveryKind: "live_demo", isContrast: true })).toBe("comparing");
    expect(choosePresentationFormat({ baseDeliveryKind: "live_demo" })).toBe("testing");
    expect(choosePresentationFormat({ baseDeliveryKind: "evidence_review" })).toBe("reviewing");
    expect(choosePresentationFormat({ baseDeliveryKind: "explanation" })).toBe("explaining");
  });
});
