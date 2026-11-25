import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { formatMoney, savingsLabel } from "../src/labels.js";

describe("formatMoney", () => {
  // @use-case:shop.storefront.labels.money#unit-tests.pounds
  it("shows pounds and pence", () => {
    assert.equal(formatMoney(1250), "£12.50");
  });
  // @use-case:end shop.storefront.labels.money#unit-tests.pounds

  // @use-case:shop.storefront.labels.money#unit-tests.unsupported
  it("refuses unknown currencies", () => {
    assert.throws(() => formatMoney(100, "JPY"), RangeError);
  });
  // @use-case:end shop.storefront.labels.money#unit-tests.unsupported
});

describe("savingsLabel", () => {
  // @use-case:shop.storefront.labels.savings#unit-tests.shows-saving
  it("shows the amount and percent saved", () => {
    assert.equal(savingsLabel(6250, 5625), "You save £6.25 (10%)");
  });
  // @use-case:end shop.storefront.labels.savings#unit-tests.shows-saving

  // @use-case:shop.storefront.labels.savings#unit-tests.nothing-saved
  it("is empty when nothing is saved", () => {
    assert.equal(savingsLabel(8900, 8900), "");
  });
  // @use-case:end shop.storefront.labels.savings#unit-tests.nothing-saved
});
