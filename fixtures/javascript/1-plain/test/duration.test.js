import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { format, parse } from "../src/duration.js";

describe("parse", () => {
  it("adds units together", () => {
    assert.equal(parse("1h 30m"), 5_400_000);
  });

  it("accepts decimals and no spaces", () => {
    assert.equal(parse("1.5h"), 5_400_000);
    assert.equal(parse("2m30s"), 150_000);
  });

  it("rejects garbage", () => {
    assert.throws(() => parse("soon"), SyntaxError);
    assert.throws(() => parse("  "), SyntaxError);
  });
});

describe("format", () => {
  it("uses the largest units first", () => {
    assert.equal(format(90_061_000), "1d 1h 1m 1s");
  });

  it("formats zero as 0s", () => {
    assert.equal(format(0), "0s");
  });

  it("round-trips", () => {
    for (const text of ["2h", "1d 4h", "45s", "1m 250ms"]) {
      assert.equal(format(parse(text)), text);
    }
  });

  it.skip("supports weeks", () => {
    assert.equal(format(604_800_000), "1w");
  });
});
