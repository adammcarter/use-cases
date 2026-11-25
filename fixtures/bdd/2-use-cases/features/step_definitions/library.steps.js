import assert from "node:assert/strict";
import { Before, Given, When, Then } from "@cucumber/cucumber";
import { Library, LoanError } from "../../src/library.js";

const date = (text) => new Date(`${text}T12:00:00Z`);

Before(function () {
  this.library = new Library();
  this.error = null;
});

Given("the library has {int} cop(y)(ies) of {string} with ISBN {string}", function (copies, title, isbn) {
  this.library.addBook(isbn, title, copies);
});

Given("{string} has borrowed {string} {int} times", function (member, isbn, times) {
  for (let i = 0; i < times; i += 1) this.library.borrow(member, isbn, date("2026-03-01"));
});

When("{string} borrows {string} on {word}", function (member, isbn, day) {
  try {
    this.loan = this.library.borrow(member, isbn, date(day));
  } catch (error) {
    if (!(error instanceof LoanError)) throw error;
    this.error = error;
  }
});

When("{string} returns {string} on {word}", function (member, isbn, day) {
  this.returned = this.library.giveBack(member, isbn, date(day));
});

When("{string} renews {string} on {word}", function (member, isbn, day) {
  return "pending";
});

Then("the loan is due on {word}", function (day) {
  assert.equal(this.loan.due.toISOString().slice(0, 10), day);
});

Then("{int} cop(y)(ies) of {string} (is)(are) left", function (count, isbn) {
  assert.equal(this.library.available(isbn), count);
});

Then("the loan is refused with {string}", function (message) {
  assert.ok(this.error, "expected the loan to be refused");
  assert.equal(this.error.message, message);
});

Then("the fine is {int} pence", function (pence) {
  assert.equal(this.returned.fine, pence);
});
