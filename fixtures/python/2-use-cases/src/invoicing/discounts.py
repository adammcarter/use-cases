from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class PercentDiscount:
    percent: Decimal

    def amount_off(self, amount: Decimal) -> Decimal:
        if not 0 <= self.percent <= 100:
            raise ValueError("percent must be between 0 and 100")
        return amount * self.percent / 100


@dataclass(frozen=True)
class FixedDiscount:
    amount: Decimal

    def amount_off(self, amount: Decimal) -> Decimal:
        return min(self.amount, amount)
