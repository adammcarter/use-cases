# Tutorial: adopt the matrix in a pure-Python repo (pytest, no JS)

This walkthrough proves the headline claim — **anyone can adopt Use Cases,
not just JavaScript repos** — by taking a tiny Python project from nothing to a
signed **FRESH** row using a **pure Python toolchain**. There is **no pnpm and no
vitest** anywhere in the project: the verifier is `pytest`.

The complete, runnable project lives at
[`examples/python-pytest/`](../../examples/python-pytest), and it is exercised
end-to-end (from the published `uc` tarball, running real `pytest`) by
[`tests/release/example-python-pytest.test.ts`](../../tests/release/example-python-pytest.test.ts).

> The only Node you install is the `uc` CLI itself (the trust engine). The code
> under test, the acceptance test, and the verifier are 100% Python.

---

## What the project looks like

```
examples/python-pytest/
├─ use-cases.yml                       # workspace config: acceptance → python.pytest preset
├─ pytest.ini                                     # importlib mode + pythonpath=src
├─ src/coupon.py                                  # implementation, wrapped in a marker block
├─ tests/use_cases/
│  └─ example.checkout.apply_coupon_test.py       # acceptance test the preset runs
└─ use-cases/checkout.yml                         # the matrix row
```

### The workspace config (`use-cases.yml`)

The `acceptance` verifier resolves to the **`python.pytest` preset** — the same
config-driven verifier model JS repos use, just pointed at pytest:

```yaml
verifiers:
  default: acceptance
  acceptance:
    preset: python.pytest      # runs: pytest tests/use_cases/{slug}_test.py
    evidence_kind: test_result
```

### The marked code (`src/coupon.py`)

`#` is the configured comment prefix for `.py`, so the marker is the Python
spelling of the same `<comment>: @use-case: <slug>` convention:

```python
#: @use-case: example.checkout.apply_coupon
COUPONS = {"SAVE10": 10, "HALF": 50}


def apply_coupon(subtotal_cents: int, code: str) -> int:
    if subtotal_cents <= 0:
        raise ValueError("subtotal must be positive")
    if code not in COUPONS:
        raise KeyError(f"unknown coupon: {code}")
    discount = subtotal_cents * COUPONS[code] // 100
    return subtotal_cents - discount
#: @use-case: end example.checkout.apply_coupon
```

### The acceptance test

The `python.pytest` preset derives the path `tests/use_cases/{slug}_test.py` from
the row id, so the test file is
`tests/use_cases/example.checkout.apply_coupon_test.py`:

```python
from coupon import apply_coupon

def test_percentage_coupon_discounts_the_subtotal():
    assert apply_coupon(1000, "SAVE10") == 900
```

`pytest.ini` makes that path collectable and importable with **no packaging
boilerplate**:

```ini
[pytest]
# importlib mode lets pytest collect the dotted row-id filename;
# pythonpath=src lets the test `from coupon import ...`.
addopts = --import-mode=importlib
pythonpath = src
```

---

## The flow: from nothing to FRESH

Install the CLI once (the only Node dependency), then drive the trust flow. These
are the exact commands the release test runs.

### 0. Install the CLI and generate a scratch signing key

```bash
npm i -g use-cases                  # provides the `uc` binary
# A throwaway ed25519 keypair. In production the PRIVATE key lives ONLY in CI.
node -e 'const c=require("crypto"),f=require("fs");const k=c.generateKeyPairSync("ed25519");
f.writeFileSync("public-key.pem",k.publicKey.export({type:"spki",format:"pem"}));
f.writeFileSync("private-key.pem",k.privateKey.export({type:"pkcs8",format:"pem"}));'
```

### 1. Validate the matrix

```bash
uc matrix validate --repo . --json     # ok: true
```

### 2. Register the binding

The marker already lives in `src/coupon.py`, so register it without editing
source:

```bash
uc bind --repo . \
  --row example.checkout.apply_coupon \
  --file src/coupon.py \
  --mode explicit --register-existing --json
```

### 3. Scan — the row is UNPROVEN

```bash
uc scan --repo . --public-key public-key.pem --json
# example.checkout.apply_coupon → UNPROVEN  (bound, but no signed proof yet)
```

### 4. Verify — runs REAL pytest (keyless)

`verify` resolves the `python.pytest` preset and actually runs
`pytest tests/use_cases/example.checkout.apply_coupon_test.py`. It holds **no
signing key** and writes an unsigned results ledger:

```bash
uc verify --repo . --all --out verification-results.jsonl \
  --public-key public-key.pem --json
# results[0].status: "pass", verifier_id: "acceptance", exit_code: 0
```

### 5. Prove — sign from the verification result (trusted CI)

`prove` consumes the unsigned results, recomputes every hash itself, and mints an
ed25519-signed proof. Locally you can use the scratch key; in production the key
is a CI secret:

```bash
UCM_SIGNING_KEY="$(cat private-key.pem)" \
uc prove --repo . --all --trusted-ci --append \
  --verification-results verification-results.jsonl \
  --signing-key-env UCM_SIGNING_KEY \
  --public-key public-key.pem --json
# rows[0].status: "signed", proof_events_appended: 1
```

### 6. Scan again — the row is FRESH

```bash
uc scan --repo . --public-key public-key.pem --json
# summary: { fresh: 1, ... }   example.checkout.apply_coupon → FRESH
```

---

## Why this is honest, not a rubber stamp

Break the production code so the genuine acceptance test fails, then re-verify:

```bash
# drop the discount in src/coupon.py, then:
uc verify --repo . --all --out verification-results.jsonl --public-key public-key.pem --json
# results[0].status: "fail", exit_code != 0
```

`prove` now refuses (`reason: RESULT_FAILED`, nothing appended) and the row stays
out of FRESH. The proof is bound to a verifier that **really ran** — exactly the
guarantee the JS path gives, delivered by a pure-Python toolchain.

| Stage | Command | Row state |
|---|---|---|
| Authored | `uc matrix validate` | (tracked) |
| Bound | `uc bind … --register-existing` | UNPROVEN |
| Verified (keyless, real pytest) | `uc verify --out …` | UNPROVEN (results only) |
| Proved (trusted, signed) | `uc prove --trusted-ci …` | **FRESH** |
| Production code broken | `uc verify` → `uc prove` | refused → not FRESH |

See [verifiers](../concepts/verifiers.md) for the full preset model and
[getting started](../getting-started.md) for the JS path and the CI workflow.
