# Example: Python + pytest

A minimal, already-wired Use Cases workspace that proves the headline
trust flow against real pytest tests. It mirrors the full walkthrough in
[`docs/tutorials/python-pytest.md`](../../docs/tutorials/python-pytest.md) — read
that for the step-by-step narrative; this README is the map.

## Layout

| Path | What it is |
|---|---|
| `use-cases.yml` | Workspace config. `verifiers.default` runs pytest. |
| `use-cases/checkout.yml` | One behaviour row: `example.checkout.apply_coupon`. |
| `src/coupon.py` | The code that satisfies the row, wrapped in `//: @use-case:` markers (Python uses `#:` comment prefix). |
| `tests/use_cases/…_test.py` | The pytest test that verifies the behaviour. |

Because the code is already marked, adopt it with `bind --register-existing`
(register the existing span) rather than a fresh `bind` (which would insert new
markers).

## Run it

```bash
# from this directory, with `use-cases` installed (npm i -g use-cases)
uc matrix validate --repo .            # matrix is clean
uc scan --repo .                       # row is UNBOUND until you register it

# register the already-marked span, then run the trust flow:
uc bind --row example.checkout.apply_coupon \
  --file src/coupon.py --register-existing
uc verify --all --out verify-results.jsonl --repo .        # runs pytest
# prove needs an ed25519 signing key — see docs/security/key-management.md:
#   node -e '...generateKeyPairSync("ed25519")...'  (one-liner in that doc)
uc prove --all --trusted-ci --signing-key-env UCM_CI_SIGNING_KEY \
  --verification-results verify-results.jsonl --append --repo .
uc scan --repo . --public-key ci-signing-key.pub.pem      # row reads FRESH

# now edit src/coupon.py inside the marked span and re-scan — it flips to SUSPECT.
```
