import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { formatMoney, savingsLabel } from "../src/labels.js";

describe("formatMoney", () => {
  it("shows pounds and pence", () => {
    assert.equal(formatMoney(1250), "£12.50");
  });

  it("refuses unknown currencies", () => {
    assert.throws(() => formatMoney(100, "JPY"), RangeError);
  });
});

describe("savingsLabel", () => {
  it("shows the amount and percent saved", () => {
    assert.equal(savingsLabel(6250, 5625), "You save £6.25 (10%)");
  });

  it("is empty when nothing is saved", () => {
    assert.equal(savingsLabel(8900, 8900), "");
  });
});
