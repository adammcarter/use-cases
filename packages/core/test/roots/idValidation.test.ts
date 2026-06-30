import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import {
  CANONICAL_ID_PATTERN,
  assertValidId,
  isValidId
} from "../../src/roots.js";
import { PresentationSkillsError } from "../../src/errors.js";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../../..");

describe("canonical id validation", () => {
  it("mirrors the common.schema.json $defs.id pattern (no drift)", () => {
    const schema = JSON.parse(
      readFileSync(resolve(repoRoot, "schemas/v1/common.schema.json"), "utf8")
    ) as { $defs: { id: { pattern: string } } };
    // The runtime guard must be exactly the schema's published id pattern.
    expect(CANONICAL_ID_PATTERN.source).toBe(schema.$defs.id.pattern);
  });

  it("accepts valid canonical ids", () => {
    for (const value of [
      "run.foo",
      "run.p9_start",
      "item.showcase.live.golden",
      "checkout.apply_coupon",
      "a",
      "a-b-c",
      "0191aaaa-bbbb-7ccc-8ddd-eeeeffff0000" // uuidv7 evidence aggregate id
    ]) {
      expect(isValidId(value), value).toBe(true);
      expect(() => assertValidId(value, "--run")).not.toThrow();
    }
  });

  it("rejects path-traversal, absolute, and separator-bearing ids", () => {
    for (const value of [
      "../../../etc/passwd",
      "..",
      "/etc/passwd",
      "run/../../escape",
      "run/sub",
      "run\\sub",
      "../escape",
      "RUN.UPPER",
      "",
      " run",
      "run ",
      ".run",
      "run."
    ]) {
      expect(isValidId(value), value).toBe(false);
      expect(() => assertValidId(value, "--run"), value).toThrow(PresentationSkillsError);
    }
  });

  it("throws a stable path.invalid_id coded error naming the parameter", () => {
    try {
      assertValidId("../../../etc/passwd", "--run");
      throw new Error("expected assertValidId to throw");
    } catch (error) {
      expect(error).toBeInstanceOf(PresentationSkillsError);
      expect((error as PresentationSkillsError).code).toBe("path.invalid_id");
      expect((error as Error).message).toContain("--run");
    }
  });
});
