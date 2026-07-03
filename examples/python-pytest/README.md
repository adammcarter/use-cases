# Example: Python + pytest

A minimal, already-wired Use Case Matrix workspace that proves the headline
trust flow against real pytest tests. It mirrors the full walkthrough in
[`docs/tutorials/python-pytest.md`](../../docs/tutorials/python-pytest.md) — read
that for the step-by-step narrative; this README is the map.

## Layout

| Path | What it is |
|---|---|
| `use-case-matrix.yml` | Workspace config. `verifiers.default` runs pytest. |
| `use-cases/checkout.yml` | One behaviour row: `example.checkout.apply_coupon`. |
| `src/coupon.py` | The code that satisfies the row, wrapped in `//: @use-case:` markers (Python uses `#:` comment prefix). |
| `tests/use_cases/…_test.py` | The pytest test that verifies the behaviour. |

Because the code is already marked, adopt it with `bind --register-existing`
(register the existing span) rather than a fresh `bind` (which would insert new
markers).

## Run it

```bash
# from this directory, with `use-case-matrix` installed (npm i -g use-case-matrix)
ucm matrix validate --repo .            # matrix is clean
ucm scan --repo .                       # row is UNBOUND until you register it

# register the already-marked span, then run the trust flow:
ucm bind --row example.checkout.apply_coupon \
  --file src/coupon.py --register-existing
ucm verify --all --out verify-results.jsonl --repo .        # runs pytest
# prove needs an ed25519 signing key — see docs/security/key-management.md:
#   node -e '...generateKeyPairSync("ed25519")...'  (one-liner in that doc)
ucm prove --all --trusted-ci --signing-key-env UCM_CI_SIGNING_KEY \
  --verification-results verify-results.jsonl --append --repo .
ucm scan --repo . --public-key ci-signing-key.pub.pem      # row reads FRESH

# now edit src/coupon.py inside the marked span and re-scan — it flips to SUSPECT.
```
