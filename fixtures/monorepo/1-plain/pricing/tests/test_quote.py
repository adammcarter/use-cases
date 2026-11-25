from decimal import Decimal

import pytest

from pricing import load_catalog, quote

catalog = load_catalog()


def test_no_discount_below_the_first_tier():
    assert quote(catalog, "coffee-beans", 4) == Decimal("50.00")


def test_best_tier_applies():
    assert quote(catalog, "coffee-beans", 5) == Decimal("56.25")
    assert quote(catalog, "coffee-beans", 12) == Decimal("127.50")


def test_items_without_tiers_are_full_price():
    assert quote(catalog, "grinder", 3) == Decimal("267.00")


def test_unknown_items_are_refused():
    with pytest.raises(KeyError, match="unknown sku"):
        quote(catalog, "teapot", 1)
