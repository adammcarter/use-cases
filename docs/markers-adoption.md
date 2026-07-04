# Use-case markers: adoption log

First real binding of a use-case row to the code that implements it, dogfooded
end-to-end with the real CLI.

## Code markers

A binding is anchored in the source by an in-code **marker comment**. `uc bind`
writes them for you, but the grammar is small enough to read and hand-edit.

### Grammar

A marker is a single source line. After optional leading whitespace it is exactly:

```
<comment-prefix>: @use-case:<slug>          # start of a span
<comment-prefix>: @use-case:end <slug>      # end of a span
```

- **`<comment-prefix>`** is the file's line-comment prefix, resolved **per file
  extension** — `//` for `.ts/.tsx/.js/.jsx/.mjs/.cjs/.swift/.c/.cc/.cpp/.cxx/.h/.hpp/.m/.mm/.java/.kt/.kts/.go/.rs/.scala`,
  and `#` for `.py/.rb/.sh/.bash/.zsh/.yaml/.yml/.toml/.pl/.r`. The map is
  config-driven (`comment_prefixes.extensions` can add or override an extension).
  An **extensionless** file (e.g. a `hooks/session-start` script) only carries
  markers when it starts with a shebang (`#!`), in which case the prefix is `#`.
- **`<slug>`** is **identity only**: a bare row id with an optional binding
  suffix — `row-id["#"binding-suffix]`. The `row-id` is dotted lowercase idents
  (`billing.checkout.happy_path`); the optional `#suffix` may also use `-`
  (`billing.checkout#fast-path`). Any extra payload after the slug
  (`fresh=`, `sha256=`, `role=`, a second token, …) is rejected — the marker
  carries no state, only the link.

Examples:

```ts
//: @use-case:billing.checkout.happy_path
export function checkout() { /* … */ }
//: @use-case:end billing.checkout.happy_path
```

```python
#: @use-case:billing.checkout.happy_path
def checkout():
    ...
#: @use-case:end billing.checkout.happy_path
```

### Bind modes

| Mode | Markers | Span | Languages |
|---|---|---|---|
| **explicit** | a start marker **and** a matching `end <slug>` | the inclusive line range between them | any language with a known prefix |
| **swift-func** | a **lone** start marker, no end | inferred from the Swift function body | Swift only |

- **explicit** brackets a precise span; the start and end slugs must match and
  spans must not nest. This is the portable default (`uc bind` explicit mode
  takes `--start-line`/`--end-line`).
- **swift-func** places a lone start marker immediately before a Swift `func`
  declaration and infers the span from the function body (`uc bind` swift-func
  mode takes `--line`). Inferred ends are **only** supported for Swift func — a
  lone start marker in any other file fails closed and demands an explicit end.

## Bound

| Use-case row | Code |
|---|---|
| `evidence.ledger.crash_durable_ledger_writes` | `packages/core/src/durableWrite.ts` :: `fsyncBestEffortForTemp` (explicit span) |

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
`packages/core/test/markers/skipBuildDirs.test.ts`.

## Next adoption steps

- Set up the real CI signing key (`UCM_CI_SIGNING_KEY` secret) so CI mints the
  first trusted proof and this row goes FRESH on `main`.
- Bind more rows to their implementing functions; track the bound/unbound ratio
  as the linkage-coverage metric.
