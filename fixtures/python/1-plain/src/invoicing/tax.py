from decimal import Decimal

TAX_RATES = {
    "uk": Decimal("0.20"),
    "de": Decimal("0.19"),
    "us-ca": Decimal("0.0725"),
    "exempt": Decimal("0"),
}


def tax_for(region: str) -> Decimal:
    try:
        return TAX_RATES[region.lower()]
    except KeyError:
        raise ValueError(f"unknown tax region: {region}") from None
