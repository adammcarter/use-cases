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
        void depositIncreasesBalance() {
            account.deposit(new BigDecimal("120.50"), "salary");
            assertEquals(new BigDecimal("120.50"), account.balance());
        }

        @ParameterizedTest
        @ValueSource(strings = {"0", "-1"})
        void depositMustBePositive(String amount) {
            assertThrows(IllegalArgumentException.class, () -> account.deposit(new BigDecimal(amount), "bad"));
        }
    }

    @Nested
    class Withdrawals {
        @Test
        void withdrawalMayUseTheOverdraft() {
            account.withdraw(new BigDecimal("30"), "groceries");
            assertEquals(new BigDecimal("-30"), account.balance());
        }

        @Test
        void withdrawalBeyondOverdraftIsRefused() {
            assertThrows(InsufficientFundsException.class, () -> account.withdraw(new BigDecimal("50.01"), "rent"));
        }
    }

    @Test
    @Disabled("interest accrual is scheduled for the next release")
    void monthlyInterestIsCredited() {
    }
}
