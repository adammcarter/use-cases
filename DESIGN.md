# Design — Variant parametrization of use-cases

> Author: orchestrator (PM), direct — Cowork/Codex backend stalled with zero model
> output across two runs, so this design was written in-repo against the real files.
> Grounded in: `verify.ts`, `verifierResolver.ts`, `verifierPresets.ts`,
> `useCases/types.ts`, `examples/basic-product/use-cases/product.yml`.

## AS BUILT — final model (supersedes §5/§6 below where they differ)

Mid-build, the marker/slug grammar (`markerLine.ts`: `row-id ["#" suffix]`) surfaced a
hard constraint: a variant id like `family::key` is not a legal bindable slug, so
variants cannot be first-class bound rows. With the user's direction ("the code slug is
the code slug — the use-cases YAML should have the parameters"), the shipped model is
the **hybrid**:

- **The family is the one bindable row.** One marker in code, one binding, the slug
  grammar untouched. `variants[]` ride along on the row as parameters.
- **verify fans out**: `--row <family>` (or `--all`, or `--dry-run`) resolves the shared
  verifier once per variant with `{variant}` substituted; each spawn's exit code is that
  variant's verdict; each variant gets its own ledger record `family::key` with its own
  `row_hash`/`binding_set_hash` (mixed over the shared family span) + `variant_key`.
  A family command lacking `{variant}` is a surfaced `VARIANT_TOKEN_MISSING` spec error.
- **scan aggregates**: the family's keyless `local_status` is `VERIFIED_LOCAL` iff every
  declared variant's record currently matches; otherwise the weakest variant status
  wins and `local_reason` names the failing variant(s). A `variant_local_status`
  breakdown array (additive) is emitted per family row.
- Ledger merge, ordinary rows, old matrices, old ledgers: all byte-identical to 0.4.1
  (pinned by the golden-hash + regression suites; 599+ core tests green).

## 1. Problem framing

Today one `uc verify` invocation proves N **independent** rows: it loops rows and,
per row, resolves that row's own verifier, spawns it, and records one verdict. A
single logical use-case that should fan into many **variants** — same behaviour,
different inputs (`0/1/many`, `empty/null`, boundary, negative) — has no first-class
representation: you either cram them into one row (losing per-variant evidence) or
author N hand-copied rows with N duplicated verifiers. We want a use-case to declare
its variants once, share ONE verifier, and have a SINGLE invocation emit a verdict
**per variant**, each recorded as its own row with its own integrity hashes.

## 2. Design decision summary

**Chosen approach — "variant family": additive `variants[]` on the use-case; ONE
shared verifier command with a `{variant}` token, spawned once per declared variant;
exit code is the verdict; all N records land in a single merge-write.**

A use-case may declare `variants: [{ key, ... }]`. Each variant is an **addressable
row** with id `family.id::variant_key`, inheriting the family's binding span but
computing its **own** `binding_set_hash`/`row_hash` (both already keyed by row_id).
The family declares ONE verifier. `uc verify` substitutes each variant's `key` into the
shared command's `{variant}` token and spawns it once per variant; **exit 0 = pass,
non-zero = fail** — the same verdict rule ordinary rows already use. All variant result
records are written in **one merge-write**. `uc scan` lists each variant row with its
own `local_status`. Non-variant use-cases and older `uc` binaries are wholly unaffected
because the use-case schema is open (`[key: string]: unknown`) and every new field is
optional.

Why exit-code-per-variant over a structured stdout report: it reuses the verifier
preset substitution machinery that already exists for `{slug}`, speaks the universal
verdict language (exit code) so any existing test command adopts with near-zero
friction, and adds **no new parser and no new schema**. The 0.4.1 merge already records
all N variants together in one atomic write regardless of spawn count, so "prove the
family in one command, all recorded together" holds without a report format.

| Rejected alternative | Why rejected |
|---|---|
| **One process emits a JSONL per-variant report** (`ucase-variant-report-v1`; exit code is NOT the verdict) | More power than v1 needs: invents a new stdout schema + a tolerant parser (the riskiest component) + an exit-code-isn't-verdict subtlety. Its one real win — a single-process binary that shares setup across variants — is a minority case. **Deferred, not dead:** it becomes an opt-in verifier mode later IF a real user hits the re-setup cost. |
| **Variants as sub-verdicts inside ONE row's record** (one `row_id`, array of variant statuses) | Breaks per-variant integrity: one `row_hash`/`binding_set_hash` can't represent N variants; `uc scan`'s row→proof derivation and the merge key (`row_id`) would need reworking; a partial-fail row has no honest single verdict. |
| **Reuse the existing `scenarios[]` axis** | `scenarios` are step-narratives with NO verifier and NO verdict; overloading them with verifier I/O muddies a shipped concept and would change `scenario` semantics for every existing matrix. Variants need verdict-bearing identity `scenarios` deliberately lack. |

## 3. Matrix representation (additive YAML)

**Before** (a normal row, unchanged and still valid):

```yaml
use_cases:
  - id: cart.quantity.golden
    title: Cart accepts a valid quantity
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: test_result
          required_verifiers: [script]
          minimum_count: 1
```

**After** (a parametrized family — everything below `variants` is new + optional):

```yaml
use_cases:
  - id: cart.quantity
    title: Cart quantity handling across input shapes
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: test_result
          required_verifiers: [script]
          minimum_count: 1
    variants:                        # NEW, optional
      - key: zero                    # required, [a-z0-9_-], unique within family
        title: Rejects a zero quantity      # optional, defaults to key
      - key: one
        title: Accepts a single unit
      - key: many
        title: Accepts a large quantity
      - key: negative
        title: Rejects a negative quantity
```

Rules: `key` is stable and unique within the family; adding/removing a variant is a
matrix edit like adding/removing a row. A family with `variants` present and non-empty
is a "variant family"; absent/empty ⇒ ordinary row (today's behaviour, byte-for-byte).

## 4. Verifier→variant contract (`{variant}` token + exit code)

The family declares ONE verifier command. `uc verify` iterates the declared variants and,
for each, substitutes the variant's `key` into the `{variant}` token before spawning —
exactly as `{slug}` is substituted today. Each spawn's **exit code is that variant's
verdict** (0 → pass, non-zero → fail), and its stdout/stderr sha256 are recorded per
variant as they already are for ordinary rows.

```yaml
# family verifier (declared once); {slug} and {variant} both substitute
verifier:
  kind: script
  command: ["npx", "vitest", "run", "tests/use-cases/{slug}.test.ts", "-t", "{variant}"]
```

```
uc verify --row cart.quantity
  → spawn: vitest … cart.quantity.test.ts -t zero      → exit 0 → pass
  → spawn: vitest … cart.quantity.test.ts -t one       → exit 0 → pass
  → spawn: vitest … cart.quantity.test.ts -t many      → exit 0 → pass
  → spawn: vitest … cart.quantity.test.ts -t negative  → exit 1 → fail
```

- A command with **no `{variant}` token** but a variant family is a spec error surfaced
  at verify time (`errors[]`): the family declared variants the command can't distinguish.
- No new stdout schema, no parser: the verdict rule is the existing per-row exit-code path,
  applied once per variant.
- **Deferred power (not in v1):** a single-process report mode (one spawn emits all
  verdicts) is a clean future addition for verifiers that share setup across variants —
  see the rejected-alternatives note in §2. v1 does not build it.

## 5. Row identity & hashes

- **Row id:** `"<family.id>::<variant.key>"` (e.g. `cart.quantity::negative`). The `::`
  separator is not otherwise legal in ids, so variant rows never collide with authored
  ids.
- **Binding:** variants **inherit the family's registered binding** (bind once, at
  `cart.quantity`). `uc verify` synthesizes each variant row's binding view from the
  family's span but computes `binding_set_hash` with the **variant row_id** (the hash
  fn already takes `rowId`), so each variant record has a distinct, correct hash.
- **`row_hash`:** computed from the variant's own loaded-row projection (family fields +
  the variant's `key`/`title`), so editing one variant only invalidates that variant.
- Net: N variants ⇒ N records, each with independent `row_hash`, `binding_set_hash`,
  `span_sha256s` (shared span, distinct set-hash), `verification_context_hash`.

## 6. CLI / UX

- `uc verify --row cart.quantity` → detects a variant family, resolves the ONE shared
  verifier, spawns it ONCE, parses the report, writes N variant records.
- `uc verify --all` → families expand to their variant rows automatically; each family
  still spawns its verifier once.
- `uc verify --row cart.quantity::negative` → optional single-variant targeting; runs
  the shared verifier once but records only that variant (others untouched by the merge).
- `uc scan` → lists each variant row (`cart.quantity::zero …`) with its own
  `local_status`. A family is VERIFIED_LOCAL-complete only when every variant row is.
- `uc bind cart.quantity …` binds the family; variants inherit. (`uc bind` on a
  variant id is allowed for an override but not required.)
- `--dry-run` reports one planned entry per variant with the shared command.

## 7. Ledger write semantics

Unchanged merge, more records. The per-variant spawns yield a
`VerificationResultRecord[]` whose `row_id`s are the variant ids. The existing merge
(keyed by `row_id`, write-temp-then-rename) already:
- replaces exactly the variant rows this run produced,
- preserves every other row (variant siblings NOT targeted, and unrelated rows),
- stays atomic.

N spawns → N records → **one** merge-write (results are collected in-memory across the
per-variant spawns, then written once). The 0.4.1 truncation fix carries over verbatim;
variant rows are just more `row_id`s in the same keyspace.

## 8. Backward-compat analysis (every schema touch)

**Correction (verified against the real validator):** the runtime validator is the
JSON Schema `use-case-file.schema.json`, and its use-case object is
`"additionalProperties": false` — NOT the permissive TS type `[key:string]:unknown`.
So compat is directional:

- **Forward — new `uc` reads any matrix:** fully compatible. An old (no-`variants`)
  matrix loads byte-identically (hash guard below). This is the direction that matters
  for existing users upgrading. ✓
- **Backward — OLD `uc` reads a NEW (`variants`-bearing) matrix:** the strict schema
  rejects the unknown `variants` key with a **loud `schema_error`** — safe (no silent
  corruption, no misread) but it means **adopting variants requires everyone on that
  repo to be on `uc ≥ 0.5.0`.** That is a documented version floor, not a break of any
  existing repo. It cannot be retrofitted into already-shipped 0.4.1 regardless.

| Touch | Kind | Safe because |
|---|---|---|
| `variants` added to `use-case-file.schema.json` (use-case object) + `variants?` on `UseCaseV1` | additive to the schema | New `uc` accepts it; no existing no-`variants` matrix is affected. Old `uc` rejects it loudly (version floor above), never misreads it. |
| `variant_key?: string` on `ucase-verification-result-v1` | additive, optional | Result records are validated by their own schema; add `variant_key` as optional there too. Records for ordinary rows omit it, so existing ledgers validate unchanged. Schema id stays v1. |
| `{variant}` token in verifier command substitution | additive | Only expands when present; existing `{slug}`-only commands are untouched. |
| Row id `::` convention | additive | Only produced for variant families; authored ids can't contain `::`. |

### The one hash trap, and the guard

`computeSemanticHash(useCase)` = `sha256(canonicalJson(the WHOLE use-case value))` — it
hashes **every** field, including ones the type doesn't name. Consequence: the ONLY way
0.5.0 could break an existing matrix is by **materialising a default** (e.g. injecting
`variants: []`, or any normalised field) onto rows the author didn't write — that would
change their `semantic_hash` silently and invalidate stored evidence.

**Build rule (enforced by test):** only ever hash what the author literally wrote; never
normalise `variants` (or anything) onto a row that omits it. Load is
pass-through for absent optional fields.

Three invariants pinned with tests: **(a)** a matrix with no `variants` produces
byte-identical `semantic_hash` + scan/verify output under 0.5.0 vs 0.4.1; **(b)** a
`variants`-bearing matrix loads cleanly under 0.5.0 AND the schema addition doesn't
change validation of any no-`variants` file; **(c)** an existing
`verification-results.jsonl` (no `variant_key`) still validates and drives `scan`
unchanged.

**Versioning:** additive for existing repos ⇒ **0.4.1 → 0.5.0 minor bump, no migration
step for old matrices** (they load unchanged under new `uc`). The one caveat is the
**version floor**: a repo that *adopts* variants requires its collaborators to be on
`uc ≥ 0.5.0`, because older clients reject the new key (strict schema). Call this out in
release notes. A `uc migrate` path is only needed if a *breaking* restructure of
existing fields is ever chosen — this design avoids that.

## 9. Failure semantics

| Situation | Behaviour |
|---|---|
| **Partial pass** (some variants fail) | Each variant row records its own `pass`/`fail` from its own spawn's exit code; family isn't "green" until all pass. This is the whole point — no conflation. |
| **Unbound family** | Every variant row records `blocked` (mirrors today's unbound-row path); scan shows them UNVERIFIED_LOCAL. No spawn happens. |
| **Command lacks a `{variant}` token** but the row is a variant family | Spec error surfaced in `errors[]` before any spawn — the command can't distinguish variants, so it must not silently prove them all identically. |
| **A variant's spawn times out** | That variant row records `fail` (exit 124 path, as ordinary rows), siblings unaffected. |
| **Verifier resolves to `mode:none` / no verifier** | Every variant row records `blocked` — same as an ordinary bound-but-unverifiable row today. |

Note how much smaller this table is than the report-based design: reusing the
exit-code verdict path means variant failure modes ARE the existing row failure modes,
applied per variant. No new "malformed report / missing line / duplicate line" class exists.

## 10. Phased TDD build plan (each increment led by its failing test)

1. **Schema (additive):** `variants?` on `UseCaseV1` + loader validation (unique keys,
   key charset), pass-through (NO default materialised). *Failing tests:* load a family
   (0/1/many variants); reject dup keys; reject bad key charset; a no-`variants` matrix
   loads with an unchanged `semantic_hash`.
2. **Row expansion:** a family expands to variant rows in the row set feeding
   verify/scan. *Failing tests:* `many`→N rows with ids `family::key`; `0 variants`⇒the
   family itself as one ordinary row (no `::` rows); ids are stable/sorted.
3. **`{variant}` substitution:** extend the existing `{slug}` substitution to also
   substitute `{variant}`. *Failing tests:* token expands per variant; a family whose
   command omits `{variant}` is a surfaced spec error.
4. **verify integration:** one spawn PER variant → N records with correct per-variant
   hashes, collected then written once. *Failing tests:* spy the injected runner → one
   spawn per declared variant; N records; each record's `binding_set_hash`/`row_hash`
   distinct + matches recompute; `variant_key` populated; **exit-code→verdict per variant**
   (parametrised: all-pass / partial-fail / all-fail).
5. **Ledger merge across variants:** verifying family A leaves family B + ordinary rows
   intact; re-verifying one variant supersedes only itself. *Failing tests:* the 0.4.1
   merge property extended to variant siblings; N spawns still yield exactly one write.
6. **scan derivation:** each variant row surfaces its own `local_status`; family
   "complete" only when all variants VERIFIED_LOCAL. *Failing tests:* mixed variant
   states; all-green family.
7. **CLI surface:** `--row family`, `--row family::key`, `--all`, `--dry-run`.
   *Failing tests:* targeting + dry-run plan lists per-variant entries, spawns nothing.
8. **Compat guards:** the three invariants from §8 as explicit regression tests
   (extend the existing cross-version release test).
9. **use-cases matrix:** add rows proving the new behaviour; `uc bind`/`verify`/`scan`
   the real feature (dogfood).

Parametrised coverage called out: variant counts `0 / 1 / many`; verdict outcomes
`all-pass / partial-fail / all-fail`; degenerate `unbound / no-{variant}-token /
timeout / mode:none`.

## 11. Flow

```
          matrix use-case (family)
          id: cart.quantity
          variants: [zero, one, many, negative]
          verifier: [... "{slug}.test.ts" "-t" "{variant}"]   (declared ONCE)
                    │
                    │  uc verify --row cart.quantity
                    ▼
          resolve shared verifier, substitute {variant} per declared key
                    │
       ┌────────────┼───────────┬───────────┬───────────────┐
       ▼            ▼           ▼           ▼    (one spawn per variant;
   -t zero      -t one      -t many    -t negative  exit code = verdict)
   exit 0       exit 0      exit 0      exit 1
       │            │           │           │
       ▼            ▼           ▼           ▼
   ┌─────────── N result records collected in-memory ───────────┐
   │ cart.quantity::zero      pass   hashes(row_id=…::zero)      │
   │ cart.quantity::one       pass   hashes(row_id=…::one)       │
   │ cart.quantity::many      pass   hashes(row_id=…::many)      │
   │ cart.quantity::negative  fail   hashes(row_id=…::negative)  │
   └────────────────────────────┬───────────────────────────────┘
                    │  ONE merge-write (keyed by row_id, atomic)
                    ▼
       .use-cases/verification-results.jsonl   (siblings + other rows preserved)
                    │
                    ▼
          uc scan → per-variant local_status; family green iff all variants green
```
