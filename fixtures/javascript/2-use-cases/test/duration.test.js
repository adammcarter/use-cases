import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { format, parse } from "../src/duration.js";

describe("parse", () => {
  // @use-case:duration.text.parse#unit-tests.adds-units
  it("adds units together", () => {
    assert.equal(parse("1h 30m"), 5_400_000);
  });
  // @use-case:end duration.text.parse#unit-tests.adds-units

  // @use-case:duration.text.parse#unit-tests.decimals-and-spacing
  it("accepts decimals and no spaces", () => {
    assert.equal(parse("1.5h"), 5_400_000);
    assert.equal(parse("2m30s"), 150_000);
  });
  // @use-case:end duration.text.parse#unit-tests.decimals-and-spacing

  // @use-case:duration.text.parse#unit-tests.garbage-refused
  it("rejects garbage", () => {
    assert.throws(() => parse("soon"), SyntaxError);
    assert.throws(() => parse("  "), SyntaxError);
  });
  // @use-case:end duration.text.parse#unit-tests.garbage-refused
});

describe("format", () => {
  // @use-case:duration.text.format#unit-tests.largest-first
  it("uses the largest units first", () => {
    assert.equal(format(90_061_000), "1d 1h 1m 1s");
  });
  // @use-case:end duration.text.format#unit-tests.largest-first

  // @use-case:duration.text.format#unit-tests.zero
  it("formats zero as 0s", () => {
    assert.equal(format(0), "0s");
  });
  // @use-case:end duration.text.format#unit-tests.zero

  // @use-case:duration.text.format#unit-tests.round-trip
  it("round-trips", () => {
    for (const text of ["2h", "1d 4h", "45s", "1m 250ms"]) {
      assert.equal(format(parse(text)), text);
    }
  });
  // @use-case:end duration.text.format#unit-tests.round-trip

  // @use-case:duration.text.format#unit-tests.weeks
  it.skip("supports weeks", () => {
    assert.equal(format(604_800_000), "1w");
  });
  // @use-case:end duration.text.format#unit-tests.weeks
});
