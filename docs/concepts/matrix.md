# Concept: the use-case matrix

The **matrix** is your repo's living acceptance specification. Instead of a static
`TEST-MATRIX.md`, it is a set of sharded YAML files — one row per behaviour your
product is supposed to exhibit — that the tooling can load, validate, plan from,
and (once bound and proved) gate releases on.

## Where it lives

Rows live under the `use_cases_dir` declared in `use-cases.yml`
(default `use-cases/`), split across as many YAML files as you like. Each file
declares a `feature` and a list of `use_cases`:

```yaml
schema_version: 1
feature:
  id: billing.core
  name: Billing
  summary: Charges are computed and applied correctly.
use_cases:
  - id: billing.core.apply_discount
    title: Apply a percentage discount to an order
    lifecycle: active
    value_tier: core
    journey_role: golden
    # … intent, preconditions, trigger, scenarios, observable_outcomes,
    #    host_applicability …
    verification_policy:
      mode: requirements        # or: none
    approval_policy:
      mode: none
```

Every persisted matrix file carries `schema_version` and is a versioned contract
(see [stability](../reference/stability.md)). The full field set is in the
[data model](../data-model.md).

## What a row carries

A row is more than a title. The fields that drive the trust engine are:

- **`id`** — the stable slug used everywhere: as the binding marker payload, the
  proof's row id, and the `{slug}` substituted into verifier commands.
- **`verification_policy`** — *how* this row is proved. `mode: none` means the row
  is tracked but never provable. `mode: requirements` lists `required_verifiers`
  that CI must run and pass; that is what lets the row become FRESH. See
  [verifiers](./verifiers.md).
- **`approval_policy`** — release-gating intent, e.g. `required_for_release`. In
  **release** policy mode a `required_for_release` row that is not FRESH blocks.

## Working with the matrix from the CLI

All matrix commands emit the standard JSON envelope and take `--json`:

| Goal | Command |
|---|---|
| Check structural integrity | `uc matrix validate --repo . --json` |
| List / filter addressable rows | `uc matrix list --repo . --json` (filters: `--value`, `--journey-role`, `--lifecycle`, `--host`, `--tag`, `--changed-path`) |
| Combine matrix + evidence status | `uc matrix status --repo . --json` |
| Add or update one row | `uc matrix upsert --repo . --file <yaml> --use-case-json '<json>' --json` |
| Retire a row | `uc matrix remove --repo . --use-case <id> --reason <text> --json` |

`matrix remove` is a **lifecycle transition**, not a physical delete: the row is
marked `lifecycle: removed` and its history is preserved. Mutations validate the
matrix before writing and refuse path escapes.

## How it fits the trust model

```
matrix row  ──bind──▶  code binding  ──verify+prove (CI)──▶  FRESH
   (this doc)        (bindings.md)         (proofs-and-ledger.md)
```

The matrix is the source of truth for *what* must hold; [bindings](./bindings.md)
connect each row to the *code* that satisfies it; [verifiers](./verifiers.md)
define *how* it is checked; and [proofs](./proofs-and-ledger.md) are the
signed CI gate that turns a checked row FRESH.

See also: [CLI reference](../cli.md) · [stability policy](../reference/stability.md).
