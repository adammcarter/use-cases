"""Acceptance test for the `example.checkout.apply_coupon` use-case row.

This is a plain pytest module — the `python.pytest` verifier preset runs it with

    pytest tests/use_cases/example.checkout.apply_coupon_test.py

(the path the preset derives from the row id). It imports the implementation via
the `pythonpath = src` setting in pytest.ini, so there is no JS toolchain here.
"""

import pytest

from coupon import apply_coupon


def test_percentage_coupon_discounts_the_subtotal():
    assert apply_coupon(1000, "SAVE10") == 900


def test_half_off_coupon():
    assert apply_coupon(2000, "HALF") == 1000


def test_unknown_coupon_is_rejected():
    with pytest.raises(KeyError):
        apply_coupon(1000, "NOPE")


def test_non_positive_subtotal_is_rejected():
    with pytest.raises(ValueError):
        apply_coupon(0, "SAVE10")
