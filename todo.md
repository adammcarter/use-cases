# Use-cases as the living source of truth

## The idea

Use-cases are the single source of truth that four delivery modes build on / use
to define and write themselves:

- acceptance tests
- unit tests
- ui tests
- showcasing / presenting

Each mode derives from a use-case row and reports back to it. The end state: the
use-case is always up to date -- a real mirror of the functionality, a product
of BOTH code and design/spec (the spec is expected to change during impl).

## Why it can work here (the mechanism)

The matrix already has the bones (actor / intent / trigger / observable_outcomes
/ verification_policy) and -- crucially -- the honesty engine:

- Evidence ledger: a row's claims are backed by recorded events, never asserted.
- Semantic-hash freshness: edit a row -> its hash changes -> prior evidence goes
  stale -> it must be re-proven. Drift surfaces itself instead of hiding.

So the row is pulled toward truth from both ends:

```
   design / spec  --writes intent-->  [ USE-CASE ]  --derives--> acceptance / ui / showcase
   code / reality --proves/refutes->  [  (row)   ]  --cites----> unit tests
                          ^                 |
                          +---- evidence ---+   (keeps the mirror TRUE)
```

## Survival rules

1. Mechanical, not manual. Building/testing/showing a row should feed evidence
   back automatically. Manual sync = drift = a false mirror, which is worse than
   no mirror.
2. Cheaper than bypass. It must be less work to keep the row in sync than to
   route around it, or people route around it.
3. Threaded spec -> delivery. The hash -> stale-evidence -> re-prove loop is what
   absorbs the spec changing during implementation.

## Relationship to the four modes

- Behavioral modes (acceptance, ui, showcasing): the row can drive / scaffold them.
- Unit tests: cite the row for coverage / traceability; not owned by it.
