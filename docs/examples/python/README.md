# Small Python Use Cases Example

A deliberately small Python repository showing:

- one root scope
- one use case with two scenarios
- an automated unit route and a non-gating procedural smoke check
- markers around the implementation and each test
- one validation resource (`fixtures/catalog.json`)
- optional groups
- optional helpers in `use-cases-bridge.yml`

Resolved use case:

```text
pyshop.cart.add-item
```

## Helpers

`use-cases-bridge.yml` runs `pytest tests/test_cart.py` for `use-cases verify --run` and reads the result with the `exit-code` transformer.

`exit-code` is a bundled transformer. It gives every validation link inside `settings.file` the same result: pass when the command exits 0, fail otherwise. It needs the exit code, so it works only with `use-cases verify --run`. Because it cannot tell the two tests apart, one failing test fails both markers; a per-test pytest transformer would remove that limit.

The use case file names no commands or tools. `.use-cases/` and `build/` are generated at runtime and are not committed.
