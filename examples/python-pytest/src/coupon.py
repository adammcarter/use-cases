"""A tiny, self-contained checkout helper an adopter might own.

The function below is the implementation the use-case row
`example.checkout.apply_coupon` describes. It is wrapped in a Use Case Matrix
marker block (the `@use-case` start/end comments below) so the matrix can bind
the row to exactly these source lines.

`#` is the configured comment prefix for `.py`, so the markers are the Python
spelling of the same convention `//` languages use. No JavaScript, pnpm, or
vitest is involved anywhere in this project.
"""

#: @use-case: example.checkout.apply_coupon
COUPONS = {
    "SAVE10": 10,  # 10% off
    "HALF": 50,  # 50% off
}


def apply_coupon(subtotal_cents: int, code: str) -> int:
    """Return the cart total in cents after applying coupon ``code``.

    Raises ``ValueError`` for a non-positive subtotal and ``KeyError`` for an
    unknown coupon code.
    """
    if subtotal_cents <= 0:
        raise ValueError("subtotal must be positive")
    if code not in COUPONS:
        raise KeyError(f"unknown coupon: {code}")
    discount = subtotal_cents * COUPONS[code] // 100
    return subtotal_cents - discount
#: @use-case: end example.checkout.apply_coupon
