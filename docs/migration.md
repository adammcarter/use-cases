# Migration

Bring an **existing, hand-rolled** record of intended behaviour into the
use-case matrix — whatever form it's in. People already track this somewhere: a
markdown table or checklist, a CSV, a spreadsheet export, a `TEST-MATRIX.md`,
release notes, a QA sign-off sheet, a wiki dump.

**The invariant, for every format:** migration preserves intended-behaviour
*coverage*, never *proof*. Old `PASS` / `FAIL` / `DONE` marks, evidence links,
screenshots, and sign-off text come across only as **review context** — they do
not create evidence JSONL, showcase runs, approvals, host support, or verified
status. Migrated rows land as **drafts** with zero proof; freshness is earned
later by binding + verifying, never inherited.

## Two paths

- **Any format → the `migration` skill (general path).** A fixed parser can't
  understand every hand-rolled layout, so the agent does the mapping: it reads
  your file, infers its structure, and writes one reviewable **draft** use case
  per item via `ucp matrix upsert`, carrying the original text + provenance. Just
  ask your agent to "migrate" / "bring in" / "import" your file and the bundled
  `migration` skill activates. See `.agents/skills/migration/SKILL.md`.
- **A standard `TEST-MATRIX.md` → `ucp migrate test-matrix` (fast path).** For the
  one canonical markdown-table format there's a deterministic importer that
  already enforces the no-laundering invariant. Use it when your source fits.

## TEST-MATRIX fast path

Run a dry-run first:

```bash
ucp migrate test-matrix \
  --repo . \
  --source TEST-MATRIX.md \
  --out use-cases/_migrated \
  --dry-run \
  --json
```

Review the report:

```text
summary.rows_seen
summary.rows_needing_review
drafts[].output_path
warnings[]
would_write[]
```

Then write draft use cases:

```bash
ucp migrate test-matrix \
  --repo . \
  --source TEST-MATRIX.md \
  --out use-cases/_migrated \
  --write \
  --json
```

## Safety Rules

Dry-run writes no files.

Write mode only writes draft YAML and a migration manifest under the selected output directory. It never writes:

```text
evidence/
showcase-runs/
host projection files
TEST-MATRIX.md
```

Output paths must stay inside the workspace data root. Keep migrated files under `use-cases/_migrated/` until a human reviews and reshapes them.

## Review Context

Generated use cases include source references like:

```text
TEST-MATRIX.md#table-1-row-3
```

Legacy status, evidence text, and notes are stored under the migration extension as review context. Current proof must be created later with evidence or showcase flows.

The key invariant:

```text
Legacy matrix status is historical context, not current proof.
```
