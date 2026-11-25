from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal

from .tax import tax_for

CENT = Decimal("0.01")


@dataclass(frozen=True)
class LineItem:
    description: str
    unit_price: Decimal
    quantity: int = 1

    def __post_init__(self):
        if self.quantity < 1:
            raise ValueError("quantity must be at least 1")
        if self.unit_price < 0:
            raise ValueError("unit price cannot be negative")

    @property
    def total(self) -> Decimal:
        return self.unit_price * self.quantity


@dataclass
class Invoice:
    region: str
    items: list[LineItem] = field(default_factory=list)
    discounts: list = field(default_factory=list)

    def add(self, item: LineItem) -> "Invoice":
        self.items.append(item)
        return self

    def apply(self, discount) -> "Invoice":
        self.discounts.append(discount)
        return self

    @property
    def subtotal(self) -> Decimal:
        return sum((item.total for item in self.items), Decimal("0"))

    @property
    def discount_total(self) -> Decimal:
        remaining = self.subtotal
        taken = Decimal("0")
        for discount in self.discounts:
            amount = min(discount.amount_off(remaining), remaining)
            taken += amount
            remaining -= amount
        return taken

    @property
    def tax(self) -> Decimal:
        return (tax_for(self.region) * (self.subtotal - self.discount_total)).quantize(CENT, ROUND_HALF_UP)

    @property
    def total(self) -> Decimal:
        return (self.subtotal - self.discount_total + self.tax).quantize(CENT, ROUND_HALF_UP)
