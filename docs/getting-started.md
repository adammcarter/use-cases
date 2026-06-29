# Getting started: zero to your first FRESH row

This is the copy-pasteable path that takes a brand-new repo from nothing to a
single use-case row that reaches **FRESH** — the state that means "trusted CI has
signed proof that the current code, its binding, and its verifier context all
still match."

> **Read this first: only CI can mint FRESH.** A row goes FRESH when a verifying
> command (`scan` / `validate-ledger`) can verify an **ed25519-signed proof**
> against a **trusted public key**. The private signing key lives **only in
> trusted CI** — never on a laptop, never in the repo. So locally you can author
> rows, bind code, and run `scan` to *see* status, but the FRESH transition
> itself happens in CI. Steps marked **(CI only)** below cannot be done from your
> machine. This is the whole point of the trust model: an agent on a developer
> box cannot manufacture a green check.

Every command shown here is a real `ucm` command. Concepts are linked to the
[concept docs](./README.md); the deeper trust mechanics live under
[`docs/concepts/`](./concepts/matrix.md).

---

## 1. Install the CLI

```bash
pnpm add -D @use-case-matrix/cli
```

This puts the `ucm` binary on your project's path (via `pnpm exec ucm …` or a
`package.json` script). The companion MCP server ships separately as
`@use-case-matrix/mcp` (binary `ucm-mcp`) if you want agents to drive the same
commands — see [the MCP contract](./mcp.md).

## 2. Scaffold the workspace with `ucm init`

One command takes a brand-new repo from nothing to a bindable, verifiable
matrix — a workspace config plus an example row that already validates:

```bash
ucm init --repo . --template js-vitest
```

- `--template` wires the default verifier: `generic` (a clearly-TODO placeholder
  command), `js-vitest` (the `js.vitest` preset), `python-pytest`
  (`python.pytest`), or `go-test` (`go.test`).
- `--component <id>` sets the component id (otherwise it is derived from the
  repo directory name).
- `--force` overwrites an existing workspace; without it, `init` refuses rather
  than clobber a `presentation-skills.yml` that already exists.
- `--json` emits the standard result envelope; omit it for a human summary that
  prints these next steps.

It writes `presentation-skills.yml` and `use-cases/example.yml`. It never
generates or writes a private key, and it does not create the GitHub workflow —
those steps are below. The generated config looks like:

```yaml
schema_version: 1
workspace_id: my-project
component_id: my-project
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
verifiers:
  default: acceptance
  acceptance:
    preset: js.vitest
    evidence_kind: test_result
```

Use-case rows live in sharded YAML files under `use_cases_dir`. See
[the matrix concept](./concepts/matrix.md). Replace the scaffolded
`use-cases/example.yml` with a real row (next step).

## 3. Add a use-case row

Create `use-cases/billing/core.yml` with one row. Model it on a real, valid row —
the shape below mirrors a row that ships in this repo:

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
    usage_frequency: common
    tags: [billing, discount]
    source_refs:
      - kind: file
        path: src/billing/discount.ts
    actor: script
    intent: Apply a percentage discount so the order total reflects the promotion.
    preconditions:
      - An order with at least one line item exists.
    trigger: A valid discount code is applied to an order.
    scenarios:
      - id: billing.core.apply_discount.happy
        kind: steps
        steps:
          - Apply a 10% code to a $100 order.
          - Confirm the total is $90.
    observable_outcomes:
      - The discounted total is correct and never negative.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: test_result
          required_verifiers: [acceptance]
          minimum_count: 1
    approval_policy:
      mode: none
```

`verification_policy.mode: requirements` is what makes this row *provable*: it
names a verifier id (`acceptance`) that CI must run and pass. We wire that id to a
real command in step 6. (`mode: none` rows are tracked but never become FRESH —
there is nothing to prove.)

Validate the matrix:

```bash
ucm matrix validate --repo . --json
```

`ok: true` / `complete: true` means the matrix is structurally clean.

## 4. Mark the implementing code

A **binding** ties the row to the exact code that satisfies it, using an in-code
marker. Markers are language-agnostic comments. Wrap the implementing span with an
explicit start/end pair (here in TypeScript, comment prefix `//`):

```ts
//: @use-case: billing.core.apply_discount
export function applyDiscount(total: number, percent: number): number {
  const discounted = total * (1 - percent / 100);
  return Math.max(0, discounted);
}
//: @use-case: end billing.core.apply_discount
```

The grammar is `<comment>: @use-case: <slug>` … `<comment>: @use-case: end
<slug>`. See [bindings & markers](./concepts/bindings.md).

## 5. Register the binding with `ucm bind`

`bind` registers the marker in the append-only binding registry, but only after
the edited file scans clean:

```bash
ucm bind \
  --repo . \
  --row billing.core.apply_discount \
  --file src/billing/discount.ts \
  --mode explicit \
  --start-line 1 \
  --end-line 5
```

- `--mode explicit` uses the start/end marker pair you placed (`--start-line` /
  `--end-line` are the inclusive span).
- `--mode swift-func --line N` instead infers a Swift function body span from a
  single marker placed before the declaration.
- Already placed the marker yourself? add `--register-existing` so `bind` only
  registers it without editing source. Use `--dry-run` to preview.

The registry defaults to `.use-cases/bindings.jsonl` under your `data_root`
(override with `--bindings`).

## 6. Declare the verifier (config-driven, any language)

The row's `required_verifiers: [acceptance]` is resolved **from config** — there
is no hard-coded test runner. Point the `acceptance` id at a real command using a
**preset** in `presentation-skills.yml`:

```yaml
# presentation-skills.yml (add this)
verifiers:
  default: acceptance
  acceptance:
    preset: js.vitest        # runs: pnpm -s vitest run tests/use-cases/{slug}.test.ts
```

`{slug}` is substituted with the row id everywhere it appears, so each row gets
its own acceptance test path.

Verifiers are **language-agnostic** — `js.vitest` is just one preset. A Python or
Make project would instead write:

```yaml
verifiers:
  default: acceptance
  acceptance:
    preset: python.pytest    # runs: pytest tests/use_cases/{slug}_test.py
```

```yaml
verifiers:
  default: acceptance
  acceptance:
    preset: make.target      # runs: make test-use-case SLUG={slug}
```

The available presets are `command.generic`, `js.vitest`, `js.npm-test`,
`python.pytest`, `go.test`, and `make.target`. You can also inline an explicit
`{ kind: script, command: [...], inputs: [...] }` on the row itself. Full model:
[verifiers](./concepts/verifiers.md).

> **Not a JS repo?** The [pure-Python tutorial](./tutorials/python-pytest.md)
> walks the *whole* flow — bind → scan → verify → prove → FRESH — for a project
> whose verifier is `pytest`, with no pnpm/vitest involved. Runnable example:
> [`examples/python-pytest/`](../examples/python-pytest).

Now write the acceptance test the preset names (e.g.
`tests/use-cases/billing.core.apply_discount.test.ts`) and make it pass locally.

## 7. See the status locally with `ucm scan`

```bash
ucm scan --repo . --product-root . --policy-mode feature --json
```

At this point the row is **UNPROVEN**: it is bound to current code, but no signed
proof exists yet. That is expected and correct — you cannot sign locally. The five
states (FRESH / SUSPECT / UNPROVEN / UNBOUND / INVALID) are explained in
[bindings](./concepts/bindings.md).

## 8. Let CI mint the proof — the row reaches FRESH **(CI only)**

FRESH happens in a trusted CI pipeline, in two stages:

1. **`verify` — keyless, runs on every PR.** It executes each bound row's resolved
   verifier and writes an **unsigned** results ledger. It holds **no signing key**,
   so a PR can prove its tests *ran and passed* without minting trust:

   ```bash
   ucm verify --repo . --product-root . --all \
     --out .use-cases/verification-results.jsonl --json
   ```

2. **`prove` — signs, runs only on the trusted branch.** It **consumes** the
   unsigned results from `verify`, recomputes every hash itself, and mints an
   ed25519-signed proof event. The private key is injected from a CI secret and is
   the **only** place signing happens:

   ```bash
   ucm prove --repo . --product-root . --all --trusted-ci --append \
     --verification-results .use-cases/verification-results.jsonl \
     --signing-key-env UCM_CI_SIGNING_KEY --key-id ci-key-1 \
     --public-key .use-cases/trusted-ci-public-key.pem --json
   ```

   Because `prove` re-derives the hashes and signs from a key agents never see,
   nobody can manufacture a passing proof by hand.

Once that signed proof is persisted back to the repo, the next `scan` (with the
trusted `--public-key` / `--keyring`) verifies the signature and the row is
**FRESH**.

Don't hand-roll this. Use the **GitHub Actions reference workflow** at
[`.github/workflows/use-cases.yml`](../.github/workflows/use-cases.yml): it runs
`validate-ledger` + `scan` on every push/PR, selects release mode on
`main` / `release/**`, and runs the optional `verify` → `prove` → persist job that
mints proofs from the `UCM_CI_SIGNING_KEY` secret. Generate the keypair following
[key management](./security/key-management.md); the CI provenance/authority model
is in [CI hardening](./security/ci-hardening.md).

---

## What you end up with

| Stage | Command | Row state |
|---|---|---|
| Authored | `ucm matrix validate` | (tracked) |
| Bound | `ucm bind …` | UNBOUND → UNPROVEN |
| Verified in CI (PR, keyless) | `ucm verify --out …` | UNPROVEN (results only) |
| Proved in CI (trusted branch) | `ucm prove --trusted-ci …` | **FRESH** |
| Code/test later weakened | `ucm scan` | SUSPECT |

When you later change the implementation or weaken the test, the embedded hashes
no longer match and the row drops to **SUSPECT** — the stale claim becomes
visible instead of being silently trusted. Re-prove in CI to return to FRESH.

Next: read the [concepts index](./README.md) to understand the matrix, bindings,
verifiers, proofs, and evidence in depth.
