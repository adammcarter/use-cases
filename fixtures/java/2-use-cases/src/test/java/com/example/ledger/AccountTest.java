package com.example.ledger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.math.BigDecimal;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class AccountTest {

    private final Account account = new Account("acc-1", new BigDecimal("50"));

    @Test
    void newAccountHasZeroBalance() {
        assertEquals(BigDecimal.ZERO, account.balance());
    }

    @Nested
    class Deposits {
        @Test
        // @use-case:ledger.accounts.deposits#unit-tests.raises-balance
        void depositIncreasesBalance() {
            account.deposit(new BigDecimal("120.50"), "salary");
            assertEquals(new BigDecimal("120.50"), account.balance());
        }
        // @use-case:end ledger.accounts.deposits#unit-tests.raises-balance

        // @use-case:ledger.accounts.deposits#unit-tests.positive-only
        @ParameterizedTest
        @ValueSource(strings = {"0", "-1"})
        void depositMustBePositive(String amount) {
            assertThrows(IllegalArgumentException.class, () -> account.deposit(new BigDecimal(amount), "bad"));
        }
        // @use-case:end ledger.accounts.deposits#unit-tests.positive-only
    }

    @Nested
    class Withdrawals {
        @Test
        // @use-case:ledger.accounts.overdraft#unit-tests.within-limit
        void withdrawalMayUseTheOverdraft() {
            account.withdraw(new BigDecimal("30"), "groceries");
            assertEquals(new BigDecimal("-30"), account.balance());
        }
        // @use-case:end ledger.accounts.overdraft#unit-tests.within-limit

        @Test
        // @use-case:ledger.accounts.overdraft#unit-tests.beyond-limit
        void withdrawalBeyondOverdraftIsRefused() {
            assertThrows(InsufficientFundsException.class, () -> account.withdraw(new BigDecimal("50.01"), "rent"));
        }
        // @use-case:end ledger.accounts.overdraft#unit-tests.beyond-limit
    }

    @Test
    @Disabled("interest accrual is scheduled for the next release")
    void monthlyInterestIsCredited() {
    }
}
