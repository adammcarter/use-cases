# Concept: verifiers

A **verifier** answers "what command proves this row?" It is the bridge between a
matrix row's `verification_policy` and a concrete command CI runs. Verifiers are
**config-driven and language-agnostic** — there is no built-in test runner
assumption.

## The command-verifier model

A row's `verification_policy` in `requirements` mode lists `required_verifiers` by
id:

```yaml
verification_policy:
  mode: requirements
  requirements:
    - evidence_kind: test_result
      required_verifiers: [acceptance]
      minimum_count: 1
```

Each id resolves to a concrete `{ kind: script, command, inputs }` triple in this
order (first match wins):

1. the row's own `verification_policy.verifiers[<id>]`;
2. the workspace config's `verifiers[<id>]` (`use-case-matrix.yml`);
3. for the default-convention id **`acceptance`**, the entry named by the
   workspace's `verifiers.default`;
4. otherwise the id is **BLOCKED** with an actionable reason (it never crashes).

An entry is either an explicit script or a **preset reference**.

### Inline (explicit) on the row

```yaml
verification_policy:
  mode: requirements
  verifiers:
    script:
      kind: script
      evidence_kind: test_result
      command: [pnpm, -s, vitest, run, tests/use-cases/apply_discount.test.ts]
      inputs: [tests/use-cases/apply_discount.test.ts]
  requirements:
    - evidence_kind: test_result
      required_verifiers: [script]
      minimum_count: 1
```

### Preset reference in the workspace config

```yaml
# use-case-matrix.yml
verifiers:
  default: acceptance
  acceptance:
    preset: js.vitest
```

## The presets

A preset is a named, reusable expansion. Every occurrence of `{slug}` is
substituted with the row id, so each row resolves to its own command and inputs:

| Preset | Expands to | Declared inputs |
|---|---|---|
| `command.generic` | *(empty — you supply the argv)* | none |
| `js.vitest` | `pnpm -s vitest run tests/use-cases/{slug}.test.ts` | `tests/use-cases/{slug}.test.ts` |
| `js.npm-test` | `npm test` | none |
| `python.pytest` | `pytest tests/use_cases/{slug}_test.py` | `tests/use_cases/{slug}_test.py` |
| `go.test` | `go test ./...` | none |
| `make.target` | `make test-use-case SLUG={slug}` | none |

An entry referencing a preset may override `inputs`, and supply `evidence_kind`
and `timeout_seconds`. `command.generic` ships an empty command on purpose: it is
the bring-your-own-argv escape hatch for any toolchain not covered by a named
preset.

## The `{slug}` convention

`{slug}` is the row id. It is substituted everywhere it appears in a preset's
`command` and `inputs` (and in inline script entries). This is what lets one
shared verifier definition fan out to a per-row test file:
`tests/use-cases/billing.core.apply_discount.test.ts`,
`tests/use-cases/billing.core.refund.test.ts`, and so on.

## `verification_context_hash`: why weakening the test drops FRESH

A proof certifies *what* was verified (row, policies, bindings, spans) and *which*
code it ran against. The **verification context hash** additionally certifies
*how* it was verified. It is a sha256 over:

- the row's `verification_policy`;
- the **resolved verifier(s)** — id, kind, `evidence_kind`, the exact command
  argv, and timeout;
- the **byte contents of every declared input file** (e.g. the acceptance test
  itself); and
- the repo lockfile (`pnpm-lock.yaml` by default), which pins the toolchain.

`prove` embeds this hash in the proof; `scan` re-derives it from the *current*
verifier and input contents. If they differ, the proof no longer matches and the
row drops to **SUSPECT** with a `VERIFICATION_CONTEXT_CHANGED` reason.

The consequence is the important part: if someone **weakens or deletes the
acceptance test** (or swaps the verifier command, or bumps the lockfile) while the
production code is untouched, the old proof can no longer cover the row. You cannot
keep a green check by quietly gutting the thing that earned it.

> Because `prove` (embed) and `scan` (re-derive) both compute this hash from the
> **same resolved workspace context**, the embedded and recomputed values agree
> byte-for-byte when nothing changed — so drift detection has no false positives.

See also: [the matrix](./matrix.md) · [bindings & freshness](./bindings.md) ·
[proofs & ledger](./proofs-and-ledger.md).
