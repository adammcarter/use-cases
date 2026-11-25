class OutOfStockError(Exception):
    pass


class Item:
    def __init__(self, sku: str, price: int, in_stock: bool = True):
        self.sku = sku
        self.price = price
        self.in_stock = in_stock


class Cart:
    def __init__(self):
        self.items = []

    # @use-case:pyshop.cart.add-item#add-item
    def add_item(self, item: Item):
        if not item.in_stock:
            raise OutOfStockError(item.sku)
        self.items.append(item)

    @property
    def total(self):
        return sum(item.price for item in self.items)
    # @use-case:end pyshop.cart.add-item#add-item
