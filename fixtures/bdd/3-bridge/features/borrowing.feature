@borrowing
Feature: Borrowing books
  Members borrow books for a fixed loan period, while copies last.

  Background:
    Given the library has 2 copies of "The Hobbit" with ISBN "9780261103344"

  # @use-case:library.borrowing.borrow#acceptance.available-copy
  Scenario: A member borrows an available book
    When "ana" borrows "9780261103344" on 2026-03-01
    Then the loan is due on 2026-03-15
    And 1 copy of "9780261103344" is left
  # @use-case:end library.borrowing.borrow#acceptance.available-copy

  # @use-case:library.borrowing.borrow#acceptance.last-copy
  Scenario: Nobody can borrow the last copy twice
    Given "ben" borrows "9780261103344" on 2026-03-01
    And "cy" borrows "9780261103344" on 2026-03-01
    When "ana" borrows "9780261103344" on 2026-03-02
    Then the loan is refused with "no copies of 9780261103344 left"
  # @use-case:end library.borrowing.borrow#acceptance.last-copy

  # @use-case:library.borrowing.loan-limit#acceptance.fourth-book
  Scenario: Members hold at most three books
    Given the library has 5 copies of "Dune" with ISBN "9780441013593"
    And "ana" has borrowed "9780441013593" 3 times
    When "ana" borrows "9780261103344" on 2026-03-02
    Then the loan is refused with "ana already has 3 books"
  # @use-case:end library.borrowing.loan-limit#acceptance.fourth-book
