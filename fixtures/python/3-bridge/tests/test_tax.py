from decimal import Decimal

import pytest

from invoicing import tax_for


# @use-case:invoicing.billing.tax-regions#unit-tests.known-rates
@pytest.mark.parametrize("region, rate", [("uk", "0.20"), ("DE", "0.19"), ("exempt", "0")])
def test_known_regions(region, rate):
    assert tax_for(region) == Decimal(rate)
# @use-case:end invoicing.billing.tax-regions#unit-tests.known-rates


# @use-case:invoicing.billing.tax-regions#unit-tests.unknown-refused
def test_unknown_region_is_rejected():
    with pytest.raises(ValueError, match="unknown tax region"):
        tax_for("mars")
# @use-case:end invoicing.billing.tax-regions#unit-tests.unknown-refused


# @use-case:invoicing.billing.tax-regions#unit-tests.reverse-charge
@pytest.mark.skip(reason="EU reverse-charge not implemented yet")
def test_reverse_charge_for_eu_business_customers():
    assert tax_for("de-b2b") == Decimal("0")
# @use-case:end invoicing.billing.tax-regions#unit-tests.reverse-charge
