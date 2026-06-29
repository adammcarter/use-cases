# TEST-MATRIX Migration

Migration preserves intended behavior coverage. It does not preserve proof.

Old `PASS`, `FAIL`, `DONE`, evidence links, screenshots, and sign-off text are imported only as review context. They do not create evidence JSONL, showcase runs, approvals, host support, or verified status.

## Recommended Flow

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
