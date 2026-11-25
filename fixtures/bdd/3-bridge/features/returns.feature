@returns
Feature: Returning books
  Books returned after their due date are fined per day late.

  Background:
    Given the library has 1 copy of "Emma" with ISBN "9780141439587"
    And "ana" borrows "9780141439587" on 2026-03-01

  Scenario: Returning on time costs nothing
    When "ana" returns "9780141439587" on 2026-03-15
    Then the fine is 0 pence

  # @use-case:library.returns.fines#acceptance.late-days
  Scenario Outline: Late returns are fined per day
    When "ana" returns "9780141439587" on <returned>
    Then the fine is <fine> pence

    Examples:
      | returned   | fine |
      | 2026-03-16 | 20   |
      | 2026-03-22 | 140  |
  # @use-case:end library.returns.fines#acceptance.late-days

  Scenario: A returned book can be borrowed again
    When "ana" returns "9780141439587" on 2026-03-10
    And "ben" borrows "9780141439587" on 2026-03-11
    Then 0 copies of "9780141439587" are left

  # @use-case:library.returns.renewal#acceptance.renew-once
  Scenario: Members can renew a loan once
    When "ana" renews "9780141439587" on 2026-03-14
    Then the loan is due on 2026-03-28
  # @use-case:end library.returns.renewal#acceptance.renew-once
