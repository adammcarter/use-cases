package com.example.ledger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class TransfersTest {

    @Test
    // @use-case:ledger.accounts.transfers#unit-tests.moves-money
    void transferMovesMoneyBetweenAccounts() {
        Account a = new Account("a", BigDecimal.ZERO);
        Account b = new Account("b", BigDecimal.ZERO);
        a.deposit(new BigDecimal("100"), "opening");
        Transfers.transfer(a, b, new BigDecimal("40"));
        assertEquals(new BigDecimal("60"), a.balance());
        assertEquals(new BigDecimal("40"), b.balance());
    }
    // @use-case:end ledger.accounts.transfers#unit-tests.moves-money

    @Test
    // @use-case:ledger.accounts.transfers#unit-tests.all-or-nothing
    void failedTransferLeavesBothAccountsUnchanged() {
        Account a = new Account("a", BigDecimal.ZERO);
        Account b = new Account("b", BigDecimal.ZERO);
        assertThrows(InsufficientFundsException.class, () -> Transfers.transfer(a, b, new BigDecimal("1")));
        assertEquals(BigDecimal.ZERO, b.balance());
    }
    // @use-case:end ledger.accounts.transfers#unit-tests.all-or-nothing
}
