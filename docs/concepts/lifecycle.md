# Concept map & lifecycle

The product has several adjacent concepts (use case, evidence, plan, showcase,
proof). This page is the one place that says how they relate, so the names don't
have to be reverse-engineered from the code. For *where* each one is stored, see
[data model](../data-model.md); for the deeper trust mechanics, see
[proofs & the ledger](./proofs-and-ledger.md).

## Glossary

| Term | What it is | Prepared or real? |
|---|---|---|
| **Use case** (matrix row) | A claimed product behaviour: intent, scenarios, value tier, observable outcomes. Authored YAML under `use-cases/`. | the claim |
| **Marker / binding** | A `@use-case:` code-span marker tying a row to the code that satisfies it, recorded in the append-only **binding registry** (`.use-cases/bindings.jsonl`). | the link |
| **Verifier** | The row's configured check (e.g. a test command) whose run is recorded. | the check |
| **Proof** | A CI-signed Ed25519 event asserting the bound code + verifier still match the row — the only thing that makes a row `FRESH`. Lives in the **proof ledger** (`.use-cases/evidence.jsonl`). | **real** (CI-attested) |
| **Use-case evidence** | Append-only *observations* attached to a use case (`evidence record`), graded by assurance — a self-reported agent "pass" is the weakest tier. Stored under `evidence/`. | **real** (but graded) |
| **Plan** | A *selected* set of high-value rows to present — `plan showcase` / `plan walkthrough`. Prepared material, not performed. | prepared |
| **Walkthrough** | A non-live, narrated plan variant (explain caveats/gaps/evidence). | prepared |
| **Capsule** | A packaged, replayable demo definition under `demo-capsules/`. | prepared |
| **Showcase** | A **performed**, event-sourced live run (`showcase start → observe → verdict → finish`) under `showcase-runs/`, with an un-fakeable user sign-off path. | **real** (performed) |

## The lifecycle

```
  AUTHOR            BIND               PROVE (CI)            PRESENT             PERFORM
  ──────            ────               ─────────            ───────             ───────
  use case  ──▶  @use-case marker ─▶  verifier runs ─▶     plan (showcase/  ─▶  showcase run
  (a claim)      + binding registry   CI signs a proof     walkthrough) or      (performed +
                                       ⇒ row is FRESH       a capsule            human sign-off)
                                            │                  (prepared)             │
                                            ▼                                         ▼
                                    use-case evidence  ◀───── observations recorded along the way ─────▶
                                    (graded, append-only)              showcase event ledger
```

Read it as: **author the claim → bind it to code → CI proves it FRESH → prepare
a plan/capsule → perform a showcase**. Nothing downstream is treated as proof
until the step that actually produces it runs — a plan is not a demo, and an
agent's self-report is not CI-signed freshness.

## Two things to keep straight

1. **"Evidence" names two different surfaces.** *Use-case evidence* (`evidence/`)
   is graded observations attached to a row. The *proof ledger*
   (`.use-cases/evidence.jsonl`) is the marker-freshness proof chain. They are
   not interchangeable — the proof ledger is the trust root; use-case evidence is
   supporting, assurance-graded material. (The ledger filename predates this
   split; treat `.use-cases/evidence.jsonl` as "the proof ledger".)

2. **Prepared ≠ performed.** Plans, walkthroughs, and capsules are *prepared
   material* — generated, not yet enacted. A **showcase** is the only thing that
   *performs* a behaviour and records real events, including a human sign-off the
   agent cannot fabricate. "Demonstrated" only ever means a showcase run.

See also: [bindings & freshness](./bindings.md) · [proofs & the ledger](./proofs-and-ledger.md) ·
[evidence vs proof](./evidence.md) · [verifiers](./verifiers.md).
