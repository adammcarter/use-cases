import { describe, expect, test } from "vitest";
import { canonicalizeSpanLines, hashSpanLines } from "../../src/markers/index.js";

describe("span canonicalizer v2", () => {
  test("hash is stable when the whole block is reindented", () => {
    const base = ["function total() {", "  return sum", "}"];
    const reindented = ["    function total() {", "      return sum", "    }"];

    expect(hashSpanLines(reindented)).toBe(hashSpanLines(base));
  });

  test("hash changes when one line changes relative indentation", () => {
    const base = ["if ready:", "  save()", "  notify()"];
    const relativeIndentChanged = ["if ready:", "  save()", "    notify()"];

    expect(hashSpanLines(relativeIndentChanged)).not.toBe(hashSpanLines(base));
  });

  test("hash is stable when blank runs are collapsed", () => {
    const base = ["load()", "", "save()"];
    const expandedBlanks = ["load()", "", "", "", "save()"];

    expect(hashSpanLines(expandedBlanks)).toBe(hashSpanLines(base));
  });

  test("hash ignores leading and trailing blank lines", () => {
    const base = ["load()", "save()"];
    const padded = ["", "", "load()", "save()", "", ""];

    expect(hashSpanLines(padded)).toBe(hashSpanLines(base));
  });

  test("hash is stable across trailing whitespace differences", () => {
    const base = ["const count = 1;", "return count;"];
    const withTrailingWhitespace = ["const count = 1;   ", "return count;\t\t"];

    expect(hashSpanLines(withTrailingWhitespace)).toBe(hashSpanLines(base));
  });

  test("hash changes for real content edits", () => {
    const base = ["const count = 1;", "return count;"];
    const contentChanged = ["const total = 1;", "return count;"];

    expect(hashSpanLines(contentChanged)).not.toBe(hashSpanLines(base));
  });

  test("mixed tabs and spaces only strip the genuinely shared prefix", () => {
    const mixedIndent = ["\t  if ready:", "\t\treturn save()", "\t  return skip()"];

    expect(canonicalizeSpanLines(mixedIndent)).toBe(
      "  if ready:\n\treturn save()\n  return skip()\n"
    );
  });

  test("empty and blank-only span bodies canonicalize to empty", () => {
    expect(canonicalizeSpanLines([])).toBe("");
    expect(canonicalizeSpanLines(["", "   ", "\t\t"])).toBe("");
  });
});
