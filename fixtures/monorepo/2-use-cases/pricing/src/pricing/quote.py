from decimal import ROUND_HALF_UP, Decimal

from .catalog import Catalog


def quote(catalog: Catalog, sku: str, quantity: int) -> Decimal:
    if quantity < 1:
        raise ValueError("quantity must be at least 1")
    item = catalog.item(sku)
    # @use-case:shop.rules.bulk-discount#pricing-tiers
    percent = max((t.percent for t in item.tiers if quantity >= t.min_quantity), default=0)
    # @use-case:end shop.rules.bulk-discount#pricing-tiers
    gross = item.unit_price * quantity
    return (gross * (100 - percent) / 100).quantize(Decimal("0.01"), ROUND_HALF_UP)
