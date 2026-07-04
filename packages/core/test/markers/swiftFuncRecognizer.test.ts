import { describe, expect, test } from "vitest";
import {
  SWIFT_FUNC_RECOGNIZER_ID,
  SPAN_CANON_ID,
  formatInferredSwiftSpanReport,
  hashSpanLines,
  recognizeSwiftFuncSpan,
  scanFileForMarkers
} from "../../src/markers/index.js";

// Find the 0-based index of the marker line in a source string.
function markerIndex(src: string): number {
  const lines = src.split("\n");
  const i = lines.findIndex((l) => l.includes("@use-case:"));
  if (i < 0) {
    throw new Error("no marker line in fixture");
  }
  return i;
}

function recognize(src: string) {
  return recognizeSwiftFuncSpan(src, markerIndex(src));
}

describe("Swift recognizer -- supported forms (spec 9.1, acceptance 1/2)", () => {
  test("#1 @MainActor public func -> span from @MainActor to closing brace", () => {
    const src = [
      "import Foundation", // line 1
      "", // 2
      "//: @use-case:checkout.apply_coupon", // 3 (marker)
      "@MainActor", // 4  <- span start
      "@available(iOS 17, *)", // 5
      "public func applyCoupon(_ code: String) async throws -> Int {", // 6
      "    return 1", // 7
      "}" // 8  <- span end
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.span.start_line).toBe(4); // the @MainActor line
    expect(r.span.end_line).toBe(8); // the closing brace line
    expect(r.symbol_name).toBe("applyCoupon");
  });

  test("#2 multiline generic signature with where-clause -> correct span", () => {
    const src = [
      "//: @use-case:checkout.apply_coupon", // 1
      "@MainActor", // 2  <- start
      "public func applyCoupon<T>(_ code: String, cart: T) async throws -> CouponResult", // 3
      "    where T: CartLike {", // 4
      "    let coupon = try await repo.find(code)", // 5
      "    return try cart.apply(coupon)", // 6
      "}" // 7  <- end
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.span.start_line).toBe(2);
    expect(r.span.end_line).toBe(7);
    expect(r.symbol_name).toBe("applyCoupon");
  });

  test("no modifiers / no attributes: span starts at the func line", () => {
    const src = ["//: @use-case:a.b", "func f() {", "  doThing()", "}"].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.span.start_line).toBe(2);
    expect(r.span.end_line).toBe(4);
  });

  test("type-member func is supported", () => {
    const src = [
      "struct Cart {",
      "    //: @use-case:cart.total",
      "    func total() -> Int {",
      "        return 0",
      "    }",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.symbol_name).toBe("total");
    expect(r.span.start_line).toBe(3);
    expect(r.span.end_line).toBe(5);
  });

  test("class func (type method) is supported; symbol name captured", () => {
    const src = [
      "class C {",
      "    //: @use-case:c.make",
      "    class func make() -> C {",
      "        return C()",
      "    }",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.symbol_name).toBe("make");
  });

  test("operator func captures the operator as the symbol name", () => {
    const src = [
      "struct V {",
      "    //: @use-case:v.eq",
      "    static func == (l: V, r: V) -> Bool {",
      "        return true",
      "    }",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.symbol_name).toBe("==");
  });

  test("extension-member func is supported, even with a where-claused header", () => {
    const src = [
      "extension Cart",
      "    where Element: Equatable {",
      "    //: @use-case:cart.dedupe",
      "    func dedupe() {",
      "    }",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.symbol_name).toBe("dedupe");
  });
});

describe("Swift recognizer -- brace matching skips strings/comments", () => {
  test("a `}` inside a string literal does NOT end the span early", () => {
    const src = [
      "//: @use-case:a.b", // 1
      "func f() {", // 2
      '    let s = "this } is not a brace"', // 3
      '    let t = "neither is this { one"', // 4
      "    // } a comment brace too", // 5
      "    /* nested /* } */ block */", // 6
      "}" // 7  <- the real closing brace
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.span.end_line).toBe(7);
  });

  test("multiline and raw strings containing braces are skipped", () => {
    const src = [
      "//: @use-case:a.b",
      "func f() {",
      '    let m = """',
      "    } still in the string {",
      '    """',
      '    let r = #"a raw } brace "# ',
      "    let n = ##\"raw ## with } brace\"##",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.span.end_line).toBe(8);
  });

  test("string interpolation with a closure brace is handled", () => {
    const src = [
      "//: @use-case:a.b",
      "func f() {",
      '    let s = "count=\\(items.map { $0 }.count)"',
      "    print(s)",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.span.end_line).toBe(5);
  });
});

describe("Swift recognizer -- placement rule (spec 9.2, acceptance 3/4/5)", () => {
  test("#3 marker AFTER @MainActor -> MARKER_INSIDE_ATTACHED_DECLARATION", () => {
    const src = [
      "@MainActor",
      "//: @use-case:checkout.apply_coupon",
      "public func applyCoupon() {",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("MARKER_INSIDE_ATTACHED_DECLARATION");
  });

  test("marker AFTER a bare modifier -> MARKER_INSIDE_ATTACHED_DECLARATION", () => {
    const src = [
      "public",
      "//: @use-case:a.b",
      "func f() {",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("MARKER_INSIDE_ATTACHED_DECLARATION");
  });

  test("#4 marker followed by a blank line -> MARKER_NOT_ADJACENT_TO_DECLARATION", () => {
    const src = [
      "//: @use-case:checkout.apply_coupon",
      "",
      "public func applyCoupon() {",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("MARKER_NOT_ADJACENT_TO_DECLARATION");
  });

  test("#5 marker followed by a comment -> MARKER_NOT_ADJACENT_TO_DECLARATION", () => {
    const src = [
      "//: @use-case:checkout.apply_coupon",
      "// TODO: coupon behavior",
      "public func applyCoupon() {",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("MARKER_NOT_ADJACENT_TO_DECLARATION");
  });
});

describe("Swift recognizer -- unsupported forms (spec 9.1, acceptance 6/7)", () => {
  test("#6 protocol requirement with no body -> FUNC_HAS_NO_BODY", () => {
    const src = [
      "protocol P {",
      "    //: @use-case:p.req",
      "    func required() -> Int",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("FUNC_HAS_NO_BODY");
  });

  test("marker before var -> NEXT_NODE_NOT_FUNC", () => {
    const src = ["//: @use-case:a.b", "var x = 1"].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("NEXT_NODE_NOT_FUNC");
  });

  test("marker before init -> NEXT_NODE_NOT_FUNC", () => {
    const src = [
      "//: @use-case:a.b",
      "init(x: Int) {",
      "    self.x = x",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("NEXT_NODE_NOT_FUNC");
  });

  test("marker before subscript -> NEXT_NODE_NOT_FUNC", () => {
    const src = [
      "//: @use-case:a.b",
      "subscript(i: Int) -> Int {",
      "    return 0",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("NEXT_NODE_NOT_FUNC");
  });

  test("marker before a computed property (var with body) -> NEXT_NODE_NOT_FUNC", () => {
    const src = [
      "//: @use-case:a.b",
      "var total: Int {",
      "    return 1",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("NEXT_NODE_NOT_FUNC");
  });

  test("#7 marker before a nested func -> NESTED_FUNC_UNSUPPORTED", () => {
    const src = [
      "func outer() {",
      "    //: @use-case:a.b",
      "    func inner() {",
      "        doThing()",
      "    }",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("NESTED_FUNC_UNSUPPORTED");
  });

  test("marker before a func inside a closure -> NESTED_FUNC_UNSUPPORTED", () => {
    const src = [
      "let handler = run {",
      "    //: @use-case:a.b",
      "    func helper() {",
      "    }",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("NESTED_FUNC_UNSUPPORTED");
  });
});

describe("Swift recognizer -- conditional compilation (spec 9.3 rule 8)", () => {
  test("declaration inside #if -> CONDITIONAL_COMPILATION_IN_SPAN", () => {
    const src = [
      "#if DEBUG",
      "//: @use-case:a.b",
      "func f() {",
      "}",
      "#endif"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("CONDITIONAL_COMPILATION_IN_SPAN");
  });

  test("#if directive inside the computed span -> CONDITIONAL_COMPILATION_IN_SPAN", () => {
    const src = [
      "//: @use-case:a.b",
      "func f() {",
      "#if DEBUG",
      "    log()",
      "#endif",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("CONDITIONAL_COMPILATION_IN_SPAN");
  });
});

describe("Swift recognizer -- another marker inside the span (spec 9.3 rule 9)", () => {
  test("a second marker inside the computed span -> ANOTHER_MARKER_INSIDE_SPAN", () => {
    const src = [
      "//: @use-case:checkout.outer",
      "@MainActor",
      "public func outer() {",
      "    //: @use-case:checkout.inner",
      "    doThing()",
      "}"
    ].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("ANOTHER_MARKER_INSIDE_SPAN");
  });
});

describe("Swift recognizer -- parse error / no closing brace", () => {
  test("func body with no closing brace -> FUNC_BODY_HAS_NO_CLOSING_BRACE", () => {
    const src = ["//: @use-case:a.b", "func f() {", "    doThing()"].join("\n");
    const r = recognize(src);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe("FUNC_BODY_HAS_NO_CLOSING_BRACE");
  });
});

// ---------------------------------------------------------------------------
// Scanner wiring (spec 2.1 rule 6, section 4.4, 9). The recognizer is reached
// through scanFileForMarkers for a lone Swift `//` marker with no explicit end.
// ---------------------------------------------------------------------------

describe("scanner wiring -- inferred Swift binding (acceptance 9 / CI print)", () => {
  const SRC = [
    "import Foundation", // 1
    "", // 2
    "//: @use-case:checkout.apply_coupon#handler", // 3 (marker)
    "@MainActor", // 4 start
    "public func applyCoupon(_ code: String) -> Int {", // 5
    "    return 1", // 6
    "}" // 7 end
  ].join("\n");

  const result = scanFileForMarkers("Sources/Checkout/CouponService.swift", SRC);

  test("produces a swift_func_inferred binding with no errors", () => {
    expect(result.errors).toEqual([]);
    expect(result.bindings).toHaveLength(1);
    const b = result.bindings[0];
    expect(b.binding_slug).toBe("checkout.apply_coupon#handler");
    expect(b.row_id).toBe("checkout.apply_coupon");
    expect(b.suffix).toBe("handler");
    expect(b.extent_kind).toBe("swift_func_inferred");
    expect(b.recognizer_id).toBe(SWIFT_FUNC_RECOGNIZER_ID);
    expect(b.span_canon_id).toBe(SPAN_CANON_ID);
    expect(b.start_marker).toEqual({ line: 3, column: 1 });
    expect(b.end_marker).toBeNull();
    expect(b.span.start_line).toBe(4);
    expect(b.span.end_line).toBe(7);
    expect(b.diagnostic).toEqual({
      symbol_kind: "swift_func",
      symbol_name: "applyCoupon",
      inferred: true
    });
  });

  test("span hash covers the declaration through the closing brace", () => {
    const b = result.bindings[0];
    const expected = hashSpanLines([
      "@MainActor",
      "public func applyCoupon(_ code: String) -> Int {",
      "    return 1",
      "}"
    ]);
    expect(b.span.sha256).toBe(expected);
  });

  test("byte offsets cover the span in the original source", () => {
    const b = result.bindings[0];
    const bytes = Buffer.from(SRC, "utf8");
    const slice = bytes.subarray(b.span.start_byte, b.span.end_byte).toString("utf8");
    expect(slice).toBe(
      "@MainActor\npublic func applyCoupon(_ code: String) -> Int {\n    return 1\n}"
    );
  });

  test("CI span report prints file, symbol, lines and span hash", () => {
    const b = result.bindings[0];
    const report = formatInferredSwiftSpanReport(b);
    expect(report).not.toBeNull();
    expect(report).toContain("INFERRED SWIFT SPAN");
    expect(report).toContain("row: checkout.apply_coupon");
    expect(report).toContain("binding: checkout.apply_coupon#handler");
    expect(report).toContain("file: Sources/Checkout/CouponService.swift");
    expect(report).toContain("symbol: applyCoupon");
    expect(report).toContain("span: lines 4-7");
    expect(report).toContain(`span_sha256: ${b.span.sha256}`);
  });
});

describe("scanner wiring -- explicit end still wins (spec 2.1 rule 6)", () => {
  test("a Swift func with explicit start+end resolves as explicit, not inferred", () => {
    const src = [
      "//: @use-case:a.b",
      "func f() {",
      "    return",
      "}",
      "//: @use-case:end a.b"
    ].join("\n");
    const result = scanFileForMarkers("f.swift", src);
    expect(result.errors).toEqual([]);
    expect(result.bindings).toHaveLength(1);
    expect(result.bindings[0].extent_kind).toBe("explicit");
  });
});

describe("scanner wiring -- unsupported inference stays INVALID (acceptance 8, 11.3)", () => {
  test("TypeScript function marker without explicit end -> UNSUPPORTED_INFERENCE", () => {
    const src = ["//: @use-case:a.b", "export function f() {}"].join("\n");
    const result = scanFileForMarkers("src/f.ts", src);
    expect(result.bindings).toHaveLength(0);
    expect(result.errors.map((e) => e.code)).toContain("UNSUPPORTED_INFERENCE");
  });

  test("Python function marker without explicit end -> UNSUPPORTED_INFERENCE", () => {
    const src = ["#: @use-case:a.b", "def f():", "    pass"].join("\n");
    const result = scanFileForMarkers("scripts/f.py", src);
    expect(result.bindings).toHaveLength(0);
    expect(result.errors.map((e) => e.code)).toContain("UNSUPPORTED_INFERENCE");
  });

  test("unsupported Swift form via the scanner is INVALID with a 9.4 code", () => {
    const src = ["//: @use-case:a.b", "var x = 1"].join("\n");
    const result = scanFileForMarkers("f.swift", src);
    expect(result.bindings).toHaveLength(0);
    expect(result.errors.map((e) => e.code)).toContain("NEXT_NODE_NOT_FUNC");
  });

  test("two separate inferred funcs in one Swift file both resolve", () => {
    const src = [
      "//: @use-case:a.one",
      "func one() {",
      "}",
      "//: @use-case:a.two",
      "func two() {",
      "}"
    ].join("\n");
    const result = scanFileForMarkers("f.swift", src);
    expect(result.errors).toEqual([]);
    expect(result.bindings.map((b) => b.binding_slug).sort()).toEqual(["a.one", "a.two"]);
    expect(result.bindings.every((b) => b.extent_kind === "swift_func_inferred")).toBe(true);
  });
});
