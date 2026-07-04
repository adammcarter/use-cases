import { describe, expect, test } from "vitest";
import {
  EXPLICIT_RECOGNIZER_ID,
  SPAN_CANON_ID,
  canonicalizeSpanLines,
  hashSpanLines,
  isValidSlug,
  normalizeNewlines,
  parseMarkerLine,
  resolveCommentPrefix,
  scanFileForMarkers,
  scanFiles,
  sha256,
  splitSlug
} from "../../src/markers/index.js";

const HEX64 = /^sha256:[0-9a-f]{64}$/;

// Acceptance #1: explicit span in a `//` file.
const SWIFT_FILE = [
  "import Foundation",
  "",
  "//: @use-case: checkout.apply_coupon#tax",
  "func computeTax() -> Int {",
  "    return 42",
  "}",
  "//: @use-case: end checkout.apply_coupon#tax"
].join("\n");

// Acceptance #2: explicit span in a configured `#` file.
const YAML_FILE = [
  "name: checkout",
  "",
  "#: @use-case: checkout.apply_coupon#yaml",
  "key: value",
  "list:",
  "  - a",
  "#: @use-case: end checkout.apply_coupon#yaml"
].join("\n");

describe("comment-prefix resolver", () => {
  test("maps `//` and `#` extensions from the default map", () => {
    expect(resolveCommentPrefix("Sources/Checkout/CouponRules.swift")).toBe("//");
    expect(resolveCommentPrefix("src/scan.ts")).toBe("//");
    expect(resolveCommentPrefix("usecases/checkout.yaml")).toBe("#");
    expect(resolveCommentPrefix("scripts/run.py")).toBe("#");
  });

  test("returns null for an unconfigured extension", () => {
    expect(resolveCommentPrefix("notes.txt")).toBeNull();
    expect(resolveCommentPrefix("Makefile")).toBeNull();
  });

  test("config overrides the default map", () => {
    expect(
      resolveCommentPrefix("weird.foo", { extensions: { ".foo": "//" } })
    ).toBe("//");
  });

  test("resolves `#` for an extensionless shebang script when contents are given", () => {
    expect(
      resolveCommentPrefix("hooks/session-start", undefined, "#!/usr/bin/env bash\nset -e\n")
    ).toBe("#");
    expect(
      resolveCommentPrefix("hooks/run", undefined, "#!/bin/sh\necho hi\n")
    ).toBe("#");
  });

  test("extensionless non-shebang files (and shebang files without contents) stay null", () => {
    // No contents -> cannot tell it is a script.
    expect(resolveCommentPrefix("hooks/session-start")).toBeNull();
    // Contents but no shebang (e.g. a Makefile) -> still null.
    expect(resolveCommentPrefix("Makefile", undefined, "all:\n\techo build\n")).toBeNull();
  });
});

describe("marker-line parser (spec 1.2/1.3)", () => {
  test("slug grammar accepts row ids and binding suffixes", () => {
    expect(isValidSlug("checkout.apply_coupon")).toBe(true);
    expect(isValidSlug("checkout.apply_coupon#tax")).toBe(true);
    expect(isValidSlug("checkout.apply_coupon#tax-rate")).toBe(true);
    expect(isValidSlug("checkout.apply_coupon#")).toBe(false);
    expect(isValidSlug("Checkout.apply")).toBe(false);
    expect(isValidSlug("checkout.apply#tax")).toBe(true);
  });

  test("splitSlug separates row id and suffix", () => {
    expect(splitSlug("checkout.apply_coupon#tax")).toEqual({
      row_id: "checkout.apply_coupon",
      suffix: "tax"
    });
    expect(splitSlug("checkout.apply_coupon")).toEqual({
      row_id: "checkout.apply_coupon",
      suffix: null
    });
  });

  test.each([
    { prefix: "//", payloadGap: "" },
    { prefix: "//", payloadGap: " " },
    { prefix: "#", payloadGap: "" },
    { prefix: "#", payloadGap: " " }
  ])("parses marker payload table for $prefix with payload gap '$payloadGap'", ({ prefix, payloadGap }) => {
    const line = (payload: string) => `${prefix}: @use-case:${payloadGap}${payload}`;

    expect(parseMarkerLine(line("checkout.apply_coupon#tax"), prefix)).toEqual({
      kind: "start",
      slug: "checkout.apply_coupon#tax",
      explicit: false,
      column: 1
    });
    expect(parseMarkerLine(line("begin checkout.apply_coupon#tax"), prefix)).toEqual({
      kind: "start",
      slug: "checkout.apply_coupon#tax",
      explicit: true,
      column: 1
    });
    expect(parseMarkerLine(line("end checkout.apply_coupon#tax"), prefix)).toEqual({
      kind: "end",
      slug: "checkout.apply_coupon#tax",
      column: 1
    });
    expect(parseMarkerLine(line("ignore:begin"), prefix)).toEqual({
      kind: "ignore-begin",
      column: 1
    });
    expect(parseMarkerLine(line("ignore:end"), prefix)).toEqual({
      kind: "ignore-end",
      column: 1
    });

    expect(parseMarkerLine(line("begin"), prefix)).toMatchObject({
      kind: "invalid",
      code: "MALFORMED_MARKER",
      message: "begin marker has no slug; expected `begin <slug>`"
    });
    expect(parseMarkerLine(line("end"), prefix)).toMatchObject({
      kind: "invalid",
      code: "MALFORMED_END_MARKER"
    });
    expect(parseMarkerLine(line("begin checkout.apply_coupon#tax extra"), prefix)).toMatchObject({
      kind: "invalid",
      code: "FORBIDDEN_MARKER_PAYLOAD",
      slug: "checkout.apply_coupon#tax"
    });
    expect(parseMarkerLine(line("end checkout.apply_coupon#tax extra"), prefix)).toMatchObject({
      kind: "invalid",
      code: "FORBIDDEN_MARKER_PAYLOAD",
      slug: "checkout.apply_coupon#tax"
    });
    expect(parseMarkerLine(line("checkout.apply_coupon#tax extra"), prefix)).toMatchObject({
      kind: "invalid",
      code: "FORBIDDEN_MARKER_PAYLOAD",
      slug: "checkout.apply_coupon#tax"
    });
    expect(parseMarkerLine(line("ignore:begin foo"), prefix)).toMatchObject({
      kind: "invalid",
      code: "FORBIDDEN_MARKER_PAYLOAD",
      message: "ignore:begin marker takes no payload"
    });
    expect(parseMarkerLine(line("ignore:end foo"), prefix)).toMatchObject({
      kind: "invalid",
      code: "FORBIDDEN_MARKER_PAYLOAD",
      message: "ignore:end marker takes no payload"
    });
    expect(parseMarkerLine(line("foo:begin"), prefix)).toMatchObject({
      kind: "invalid",
      code: "MALFORMED_MARKER",
      message: "unknown block path"
    });
    expect(parseMarkerLine(line("ignore:middle"), prefix)).toMatchObject({
      kind: "invalid",
      code: "MALFORMED_MARKER",
      message: "unknown block path"
    });
  });

  test("preserves marker column with leading indentation", () => {
    expect(parseMarkerLine("  //: @use-case:end checkout.apply_coupon#tax", "//")).toEqual({
      kind: "end",
      slug: "checkout.apply_coupon#tax",
      column: 3
    });
  });

  test("ignores ordinary lines and comments", () => {
    expect(parseMarkerLine("let x = 1", "//").kind).toBe("none");
    expect(parseMarkerLine("// a normal comment", "//").kind).toBe("none");
  });
});

describe("span canonicalizer ucase-span-lines-v1 (spec 3)", () => {
  test("strips trailing ws, preserves leading ws / blanks, single trailing LF", () => {
    const canonical = canonicalizeSpanLines(["  keep_indent()  ", "", "\ttabbed\t"]);
    expect(canonical).toBe("  keep_indent()\n\n\ttabbed\n");
    expect(hashSpanLines(["  keep_indent()  ", "", "\ttabbed\t"])).toBe(sha256(canonical));
  });

  test("normalizes CRLF and CR to LF", () => {
    expect(normalizeNewlines("a\r\nb\rc\nd")).toBe("a\nb\nc\nd");
  });

  test("empty body canonicalizes to empty string", () => {
    expect(canonicalizeSpanLines([])).toBe("");
  });
});

describe("explicit span scan -- acceptance #1 (// file)", () => {
  const result = scanFileForMarkers("Sources/Checkout/CouponRules.swift", SWIFT_FILE);

  test("scans exactly one valid binding with no errors", () => {
    expect(result.errors).toEqual([]);
    expect(result.comment_prefix).toBe("//");
    expect(result.bindings).toHaveLength(1);
  });

  test("produces the spec 4.4 explicit binding record", () => {
    const binding = result.bindings[0];
    expect(binding.binding_slug).toBe("checkout.apply_coupon#tax");
    expect(binding.row_id).toBe("checkout.apply_coupon");
    expect(binding.suffix).toBe("tax");
    expect(binding.extent_kind).toBe("explicit");
    expect(binding.recognizer_id).toBe(EXPLICIT_RECOGNIZER_ID);
    expect(binding.span_canon_id).toBe(SPAN_CANON_ID);
    expect(binding.start_marker).toEqual({ line: 3, column: 1 });
    expect(binding.end_marker).toEqual({ line: 7, column: 1 });
    expect(binding.span.start_line).toBe(4);
    expect(binding.span.end_line).toBe(6);
    expect(binding.diagnostic).toEqual({ inferred: false });
  });

  test("span lines are exactly the body between markers, with a stable hash", () => {
    const binding = result.bindings[0];
    const expectedCanonical = "func computeTax() -> Int {\n    return 42\n}\n";
    expect(binding.span.sha256).toBe(sha256(expectedCanonical));
    expect(binding.span.sha256).toMatch(HEX64);
  });

  test("byte offsets cover the span body in the original file", () => {
    const binding = result.bindings[0];
    const bytes = Buffer.from(SWIFT_FILE, "utf8");
    const slice = bytes.subarray(binding.span.start_byte, binding.span.end_byte).toString("utf8");
    expect(slice).toBe("func computeTax() -> Int {\n    return 42\n}\n");
  });
});

describe("explicit span scan -- acceptance #2 (configured # file)", () => {
  const result = scanFileForMarkers("usecases/checkout.yaml", YAML_FILE);

  test("scans correctly with prefix #", () => {
    expect(result.errors).toEqual([]);
    expect(result.comment_prefix).toBe("#");
    expect(result.bindings).toHaveLength(1);
    const binding = result.bindings[0];
    expect(binding.binding_slug).toBe("checkout.apply_coupon#yaml");
    expect(binding.span.sha256).toBe(sha256("key: value\nlist:\n  - a\n"));
  });
});

describe("explicit span scan -- ignore regions", () => {
  function scanSwiftBody(bodyLines: string[]) {
    const contents = [
      "//: @use-case: begin checkout.apply_coupon",
      ...bodyLines,
      "//: @use-case: end checkout.apply_coupon"
    ].join("\n");
    return scanFileForMarkers("f.swift", contents);
  }

  test("ignored region content changes do not change the span hash", () => {
    const before = scanSwiftBody([
      "keptBefore()",
      "//: @use-case:ignore:begin",
      "ignoredValue(1)",
      "//: @use-case:ignore:end",
      "keptAfter()"
    ]);
    const after = scanSwiftBody([
      "keptBefore()",
      "//: @use-case:ignore:begin",
      "ignoredValue(2)",
      "ignoredValue(3)",
      "//: @use-case:ignore:end",
      "keptAfter()"
    ]);

    expect(before.errors).toEqual([]);
    expect(after.errors).toEqual([]);
    expect(before.bindings[0].span.sha256).toBe(after.bindings[0].span.sha256);
  });

  test("non-ignored body line changes still change the span hash", () => {
    const before = scanSwiftBody([
      "keptBefore()",
      "//: @use-case:ignore:begin",
      "ignoredValue(1)",
      "//: @use-case:ignore:end",
      "keptAfter()"
    ]);
    const after = scanSwiftBody([
      "keptBefore()",
      "//: @use-case:ignore:begin",
      "ignoredValue(1)",
      "//: @use-case:ignore:end",
      "keptAfterChanged()"
    ]);

    expect(before.errors).toEqual([]);
    expect(after.errors).toEqual([]);
    expect(before.bindings[0].span.sha256).not.toBe(after.bindings[0].span.sha256);
  });

  test("ignore marker lines are excluded from the span hash", () => {
    const result = scanSwiftBody([
      "keptBefore()",
      "//: @use-case:ignore:begin",
      "// marker line should not hash",
      "//: @use-case:ignore:end",
      "keptAfter()"
    ]);

    expect(result.errors).toEqual([]);
    expect(result.bindings[0].span.sha256).toBe(sha256("keptBefore()\nkeptAfter()\n"));
  });

  test("ignore begin without end fails closed", () => {
    const result = scanSwiftBody([
      "keptBefore()",
      "//: @use-case:ignore:begin",
      "ignoredValue(1)",
      "keptAfter()"
    ]);

    expect(result.errors.map((e) => e.code)).toContain("UNBALANCED_IGNORE");
    expect(result.bindings).toHaveLength(0);
  });

  test("ignore end without begin fails closed", () => {
    const result = scanSwiftBody(["keptBefore()", "//: @use-case:ignore:end", "keptAfter()"]);

    expect(result.errors.map((e) => e.code)).toContain("UNBALANCED_IGNORE");
    expect(result.bindings).toHaveLength(0);
  });

  test("nested ignore begin fails closed", () => {
    const result = scanSwiftBody([
      "keptBefore()",
      "//: @use-case:ignore:begin",
      "ignoredValue(1)",
      "//: @use-case:ignore:begin",
      "ignoredValue(2)",
      "//: @use-case:ignore:end",
      "keptAfter()"
    ]);

    expect(result.errors.map((e) => e.code)).toContain("UNBALANCED_IGNORE");
    expect(result.bindings).toHaveLength(0);
  });
});

describe("explicit span scan -- INVALID detections (acceptance #3-#8)", () => {
  function codes(file: string, path = "f.swift"): string[] {
    return scanFileForMarkers(path, file).errors.map((e) => e.code);
  }

  test("#3 naked end fails (MALFORMED_END_MARKER)", () => {
    const codeList = codes(["//: @use-case: end"].join("\n"));
    expect(codeList).toContain("MALFORMED_END_MARKER");
  });

  test("#4 mismatched end fails (MISMATCHED_END_MARKER)", () => {
    const file = [
      "//: @use-case: checkout.apply_coupon",
      "body()",
      "//: @use-case: end checkout.other_row"
    ].join("\n");
    const result = scanFileForMarkers("f.swift", file);
    expect(result.errors.map((e) => e.code)).toContain("MISMATCHED_END_MARKER");
    expect(result.bindings).toHaveLength(0);
  });

  test("#5 duplicate start slug fails (DUPLICATE_BINDING_SLUG)", () => {
    const file = [
      "//: @use-case: checkout.apply_coupon",
      "a()",
      "//: @use-case: end checkout.apply_coupon",
      "//: @use-case: checkout.apply_coupon",
      "b()",
      "//: @use-case: end checkout.apply_coupon"
    ].join("\n");
    expect(codes(file)).toContain("DUPLICATE_BINDING_SLUG");
  });

  test("#6 nested span fails (NESTED_SPAN)", () => {
    const file = [
      "//: @use-case: checkout.outer",
      "x()",
      "//: @use-case: checkout.inner",
      "y()",
      "//: @use-case: end checkout.inner",
      "//: @use-case: end checkout.outer"
    ].join("\n");
    const result = scanFileForMarkers("f.swift", file);
    expect(result.errors.map((e) => e.code)).toContain("NESTED_SPAN");
    expect(result.bindings).toHaveLength(0);
  });

  test("#7 forbidden payload fails (sha256=...)", () => {
    expect(codes(["//: @use-case: checkout.apply_coupon sha256=abc"].join("\n"))).toContain(
      "FORBIDDEN_MARKER_PAYLOAD"
    );
    // Other forbidden payloads from spec 1.2.
    expect(codes(["//: @use-case: checkout.apply_coupon fresh=true"].join("\n"))).toContain(
      "FORBIDDEN_MARKER_PAYLOAD"
    );
    expect(codes(["//: @use-case: checkout.apply_coupon role=impl"].join("\n"))).toContain(
      "FORBIDDEN_MARKER_PAYLOAD"
    );
    expect(codes(["//: @use-case: checkout.apply_coupon tier1"].join("\n"))).toContain(
      "FORBIDDEN_MARKER_PAYLOAD"
    );
  });

  test("#8 single marker with no explicit end fails for non-Swift (UNSUPPORTED_INFERENCE)", () => {
    // Phase 4 note: a single Swift `func` marker now resolves via the inferred
    // recognizer, so the "unsupported inference" case is a non-Swift file. A
    // TypeScript function without an explicit end stays unsupported (spec 2.1
    // rule 5 / 11.3).
    const file = [
      "//: @use-case: checkout.apply_coupon",
      "export function applyCoupon() {}"
    ].join("\n");
    const result = scanFileForMarkers("f.ts", file);
    expect(result.errors.map((e) => e.code)).toContain("UNSUPPORTED_INFERENCE");
    expect(result.bindings).toHaveLength(0);
  });

  test("end without start fails (END_WITHOUT_START)", () => {
    expect(codes(["//: @use-case: end checkout.apply_coupon"].join("\n"))).toContain(
      "END_WITHOUT_START"
    );
  });
});

describe("scanFiles aggregator", () => {
  test("aggregates bindings and reports cross-file duplicate slugs", () => {
    const result = scanFiles([
      { file_path: "a.swift", contents: SWIFT_FILE },
      { file_path: "b.swift", contents: SWIFT_FILE }
    ]);
    expect(result.bindings).toHaveLength(2);
    expect(result.errors.map((e) => e.code)).toContain("DUPLICATE_BINDING_SLUG");
  });

  test("skips files with no configured comment prefix", () => {
    const result = scanFiles([{ file_path: "notes.txt", contents: SWIFT_FILE }]);
    expect(result.files[0].comment_prefix).toBeNull();
    expect(result.bindings).toHaveLength(0);
    expect(result.errors).toHaveLength(0);
  });
});
