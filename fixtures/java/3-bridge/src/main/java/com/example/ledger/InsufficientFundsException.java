package com.example.ledger;

import java.math.BigDecimal;

public final class InsufficientFundsException extends RuntimeException {
    public InsufficientFundsException(String accountId, BigDecimal amount) {
        super("account " + accountId + " cannot cover " + amount);
    }
}
