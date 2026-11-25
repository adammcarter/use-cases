package com.example.ledger;

import java.math.BigDecimal;

public final class Transfers {
    private Transfers() {}

    public static void transfer(Account from, Account to, BigDecimal amount) {
        if (from == to) {
            throw new IllegalArgumentException("cannot transfer to the same account");
        }
        from.withdraw(amount, "transfer to " + to.id());
        to.deposit(amount, "transfer from " + from.id());
    }
}
