import json
from pathlib import Path

import pytest

from src.shop.cart import Cart, Item, OutOfStockError


CATALOG = json.loads(Path("fixtures/catalog.json").read_text())


# @use-case:pyshop.cart.add-item#unit-tests.in-stock
def test_in_stock_item_is_added_and_totaled():
    cart = Cart()
    item = Item("sku-1", CATALOG["sku-1"]["price"], in_stock=True)

    cart.add_item(item)

    assert len(cart.items) == 1
    assert cart.total == CATALOG["sku-1"]["price"]
# @use-case:end pyshop.cart.add-item#unit-tests.in-stock


# @use-case:pyshop.cart.add-item#unit-tests.out-of-stock
def test_out_of_stock_item_is_rejected():
    cart = Cart()
    item = Item("sku-2", CATALOG["sku-2"]["price"], in_stock=False)

    with pytest.raises(OutOfStockError):
        cart.add_item(item)

    assert cart.items == []
# @use-case:end pyshop.cart.add-item#unit-tests.out-of-stock
