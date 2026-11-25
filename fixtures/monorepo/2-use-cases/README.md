# shop

Monorepo for the coffee shop: a shared price catalog, the pricing service (Python), the checkout service (Go), and storefront display helpers (JavaScript).

```text
catalog/      prices.json, shared by every service
pricing/      quotes for the product pages        (Python)
checkout/     cart totals at checkout             (Go)
storefront/   money and savings labels            (JavaScript)
```

```sh
make test
```
