from decimal import Decimal

import pytest

from invoicing import FixedDiscount, Invoice, LineItem, PercentDiscount


# @use-case:invoicing.billing.totals#unit-tests.sum-lines
def test_subtotal_adds_every_line():
    invoice = Invoice("exempt").add(LineItem("Widget", Decimal("2.50"), 4)).add(LineItem("Gadget", Decimal("10")))
    assert invoice.subtotal == Decimal("20.00")
# @use-case:end invoicing.billing.totals#unit-tests.sum-lines


# @use-case:invoicing.billing.totals#unit-tests.tax-after-discount
def test_uk_tax_is_applied_after_discounts():
    invoice = Invoice("uk").add(LineItem("Service", Decimal("100"))).apply(PercentDiscount(Decimal("10")))
    assert invoice.tax == Decimal("18.00")
    assert invoice.total == Decimal("108.00")
# @use-case:end invoicing.billing.totals#unit-tests.tax-after-discount


# @use-case:invoicing.billing.discounts#unit-tests.capped-at-zero
def test_discounts_never_make_the_total_negative():
    invoice = Invoice("exempt").add(LineItem("Sticker", Decimal("3"))).apply(FixedDiscount(Decimal("5")))
    assert invoice.total == Decimal("0.00")
# @use-case:end invoicing.billing.discounts#unit-tests.capped-at-zero


@pytest.mark.parametrize("quantity", [0, -1])
def test_line_items_need_a_positive_quantity(quantity):
    with pytest.raises(ValueError):
        LineItem("Widget", Decimal("1"), quantity)


# @use-case:invoicing.billing.totals#unit-tests.round-half-up
def test_rounding_is_half_up_to_the_cent():
    invoice = Invoice("us-ca").add(LineItem("Book", Decimal("9.99")))
    assert invoice.tax == Decimal("0.72")
# @use-case:end invoicing.billing.totals#unit-tests.round-half-up
