package com.example.ledger;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class Account {
    private final String id;
    private final BigDecimal overdraftLimit;
    private final List<Entry> entries = new ArrayList<>();

    public Account(String id, BigDecimal overdraftLimit) {
        if (overdraftLimit.signum() < 0) {
            throw new IllegalArgumentException("overdraft limit cannot be negative");
        }
        this.id = id;
        this.overdraftLimit = overdraftLimit;
    }

    public String id() {
        return id;
    }

    public BigDecimal balance() {
        return entries.stream().map(Entry::amount).reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    // @use-case:ledger.accounts.deposits#deposit
    public void deposit(BigDecimal amount, String memo) {
        requirePositive(amount);
        entries.add(new Entry(amount, memo));
    }
    // @use-case:end ledger.accounts.deposits#deposit

    // @use-case:ledger.accounts.overdraft#withdraw
    public void withdraw(BigDecimal amount, String memo) {
        requirePositive(amount);
        if (balance().subtract(amount).compareTo(overdraftLimit.negate()) < 0) {
            throw new InsufficientFundsException(id, amount);
        }
        entries.add(new Entry(amount.negate(), memo));
    }
    // @use-case:end ledger.accounts.overdraft#withdraw

    public List<Entry> history() {
        return Collections.unmodifiableList(entries);
    }

    private static void requirePositive(BigDecimal amount) {
        if (amount.signum() <= 0) {
            throw new IllegalArgumentException("amount must be positive");
        }
    }

    public record Entry(BigDecimal amount, String memo) {}
}
