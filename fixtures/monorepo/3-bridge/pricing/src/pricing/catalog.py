import json
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path

DEFAULT = Path(__file__).resolve().parents[3] / "catalog" / "prices.json"


@dataclass(frozen=True)
class Tier:
    min_quantity: int
    percent: int


@dataclass(frozen=True)
class Item:
    sku: str
    unit_price: Decimal
    tiers: tuple[Tier, ...]


@dataclass(frozen=True)
class Catalog:
    currency: str
    items: dict[str, Item]

    def item(self, sku: str) -> Item:
        try:
            return self.items[sku]
        except KeyError:
            raise KeyError(f"unknown sku: {sku}") from None


def load_catalog(path: Path = DEFAULT) -> Catalog:
    raw = json.loads(Path(path).read_text())
    items = {
        sku: Item(sku, Decimal(entry["unit_price"]), tuple(Tier(t["min"], t["percent"]) for t in entry["bulk"]))
        for sku, entry in raw["items"].items()
    }
    return Catalog(raw["currency"], items)
