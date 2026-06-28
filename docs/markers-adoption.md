# Use-case markers: adoption log

First real binding of a use-case row to the code that implements it, dogfooded
end-to-end with the real CLI.

## Bound

| Use-case row | Code |
|---|---|
| `presentation_skills.evidence.crash_durable_ledger_writes` | `packages/ucm-core/src/durableWrite.ts` :: `fsyncBestEffortForTemp` (explicit span) |

Registration: `.use-cases/bindings.jsonl`. Current status on a clean checkout:
**UNPROVEN** (linked, awaiting a trusted CI proof) — 1 row bound, 81 unbound.
That unbound count is the honest linkage-completeness baseline, not a hidden gap.

## Demonstrated loop (real code)

```
bind   -> UNPROVEN
prove  -> FRESH                         (CI verifies + ed25519-signs)
edit fsyncBestEffortForTemp body -> SUSPECT [CODE_SPAN_CHANGED]
prove  -> FRESH
```

The demo proof was signed with a throwaway key and is NOT committed; the
committed state is "bound, unproven" so the real CI signing key mints the first
trusted proof.

## Finding fixed while dogfooding

`scan` also walked `dist/`, where tsc preserves the `//:` marker comment from
source — that read as a duplicate slug (src + dist) and marked the row INVALID.
Fixed: `collectSourceInputs` now skips common build-output dirs
(`dist`, `dist-ts`, `build`, `out`, `coverage`, `.next`, `.turbo`, `.svelte-kit`)
in addition to `.git` / `node_modules` / `.use-cases`. Covered by
`test/markers/skipBuildDirs.test.ts`.

## Next adoption steps

- Set up the real CI signing key (`UCM_CI_SIGNING_KEY` secret) so CI mints the
  first trusted proof and this row goes FRESH on `main`.
- Bind more rows to their implementing functions; track the bound/unbound ratio
  as the linkage-coverage metric.
