# 08 — Links: markers and manual bindings

A link connects a use case to repository reality. Links are optional: a use case with none is still READY, and the core still works.

## Two ways to link, both optional

```text
 code ── @use-case: marker ──▶ use case                     (no YAML entry needed)
 use case YAML ── manual binding: file + lines ──▶ code    (code stays untouched)
```

| | Marker | Manual binding |
|---|---|---|
| Written in | the code, as a comment pair | the use case YAML |
| Points | from code to a use case | from a use case to a file or range |
| Moves with the code | yes | no: a line range must be updated after refactors |
| Needs a YAML entry | no | yes |
| Works in files that can't hold comments | no | yes (whole-file bindings) |

A third source, link transformers, can add links beyond these two (`10 — Bridge settings + transformer contract`). The core treats every link the same way, whatever its source.

## Placement defines role

There is no `role` field.

```text
marker <use-case-id>#<binding-id>             -> implementation link
marker <use-case-id>#<route-id>.<binding-id>  -> validation link for that route

use_case.bindings[]                           -> implementation links
validation[].bindings[]                       -> validation links for that route
```

- **Implementation links** feed freshness only.
- **Validation links** sit around the tests that prove a route. Each one expects a result when tests run (`07 — Verification State Model`).

## Cardinality

```text
implementation links    0..N   (DRAFT and READY)
validation links        0..N per route
```

Links never affect authored state. Missing links produce warnings only:

```text
use case has no implementation links
  -> freshness will not track its code

gating route has no validation links and no procedure
  -> only `use-cases record` can verify it
```

These belong to each use case, in `status` (chapter 16 §9). Neither `links` nor `validate` lists them.

## Binding ID uniqueness

Binding IDs follow `05 — Identity & ID Grammar`.

- Implementation binding IDs are unique within the use case.
- Validation binding IDs are unique within their validation route.
- One binding identity has one source. A marker and a manual binding (or a links transformer, chapter 10) must not share the same derived identity. A clash is INVALID.

The same local binding ID may appear in different collections because the derived identities differ.

## Link keys

The core assigns every resolved link a key:

```text
<use-case-id>#[<route-id>.]<binding-id>@<file>:<start-line>
```

Transformers name links by this key when they report results. A key is a handle for one run, not persistent identity.

# Markers

## Marker identity

A marker names its link completely. It needs no YAML entry.

Implementation marker:

```text
<use-case-id>#<binding-id>
```

Example:

```text
app.auth.login.authenticate#authenticate-request
```

Validation marker:

```text
<use-case-id>#<route-id>.<binding-id>
```

Example:

```text
app.auth.login.authenticate#unit-tests.valid-credentials
```

Rules:

```text
use case does not exist           -> WARNING: marker for unknown use case
route does not exist              -> WARNING: marker for unknown route
malformed marker id               -> WARNING: malformed marker
```

Such markers resolve to no link. They never make the workspace invalid, because code may run ahead of its use cases. (A pair that is not well formed is INVALID whatever the marker names: see Pairing.)

One marker identity may resolve to many distinct regions.

```text
1 marker identity -> N regions = valid
```

A YAML binding with `kind: marker` is INVALID: markers are found in the code and need no entry.

## Marker sentinels

The core recognizes only the sentinel text:

```text
@use-case:<marker-id>
@use-case:end <marker-id>
```

The core has no language or comment-syntax model.

All of these may be valid:

```text
// @use-case:app.login#submit
# @use-case:app.login#submit
^^^ @use-case:app.login#submit ^^^
REM @use-case:app.login#submit
```

Surrounding text is not interpreted.

The grammar, exactly:

```text
every occurrence of the bytes  @use-case:  is a sentinel
  followed by  end  and one or more spaces or tabs   -> an end sentinel; the id follows
  otherwise                                          -> a start sentinel; the id follows directly
the id   = the longest run of the characters  a-z 0-9 . # -  that follows,
           less any trailing  -  or  .  (no id can end with them)
```

So the id ends at the first character no id can hold, whatever the file's syntax: `<!--@use-case:a#b-->`, `/*@use-case:a#b*/` and a notebook cell's `"# @use-case:a#b\n",` all name `a#b`. But an id run directly followed by an ASCII letter, digit or underscore is not an id at all, because the author meant a longer name the grammar cannot hold: `@use-case:a.b#submiT` and `@use-case:a.b#c_d` are malformed, never read as `a.b#submi` and `a.b#c`. A sentinel whose id is malformed (empty, uppercase, a bad segment) is ignored with a warning and takes no part in pairing, but its line is still a sentinel line. Where one sentinel follows another directly (`@use-case:@use-case:a#b`), each is judged on its own.

### Pairing

Pairing is by position, first to last through the file, like brackets. It is the same for every language.

Nested different markers are valid:

```text
start A
  start B
  end B
end A
```

These make the workspace INVALID, because the region cannot be read safely:

```text
an end with no start                         end A
a start never closed                         start A ...(end of file)
crossing pairs                               start A, start B, end A, end B
the same marker nested inside itself         start A, start A, end A, end A
```

A sentinel whose id is malformed is ignored with a warning and takes no part in pairing.

Pairing comes before the use-case lookup. A start never closed, or an end with no start, is INVALID even when its use case or route does not exist. Only a malformed marker id skips pairing.

A file that holds marker text as data, not as code (test data, a fixture, a copy in build output), meets the same rules, so the two messages for an unpaired sentinel name the way out:

```text
tests/fixtures/sample.swift:3: marker 'shop.cart.add#add-item' is never closed: no '@use-case:end shop.cart.add#add-item' follows it; if this file holds marker text as data, exclude it with discovery.exclude in use-cases.yml
tests/fixtures/sample.swift:9: the end of marker 'shop.cart.add#add-item' has no start before it; if this file holds marker text as data, exclude it with discovery.exclude in use-cases.yml
```

An excluded folder is never scanned for markers (chapter 04).

### The linked region

The region is exact bytes, decided by where the two sentinels sit:

```text
line mode       start and end on different lines
                the whole lines strictly between the two sentinel lines,
                leaving out every line that holds any sentinel (any occurrence of @use-case:)

                  // @use-case:app.login#submit        <- sentinel line: not content
                  validate(form)                       <- content
                  // @use-case:app.audit#log           <- sentinel line (nested): not content
                  audit(form)                          <- content
                  // @use-case:end app.audit#log       <- sentinel line: not content
                  // @use-case:end app.login#submit    <- sentinel line: not content

same-line mode  start and end on the same line
                the bytes strictly between the two sentinel tokens, less the bytes of every
                sentinel token inside them

                  /* @use-case:app.login#submit */ submit() /* @use-case:end app.login#submit */
                                                  └──────────────┘ content: " */ submit() /* "
```

Consequences:

- decoration on a sentinel line (the comment syntax, trailing text) is never content, so rewrapping a comment changes nothing;
- in line mode, adding or removing a nested marker never changes the outer region's content;
- in same-line mode, a nested marker's tokens are left out but the comment syntax around them stays, because no language-neutral rule can tell comment syntax from code. Nest inside a same-line region only when that is acceptable;
- code that shares a line with a sentinel is not part of an outer line-mode region. Put sentinels on lines of their own;
- line breaks are CR, LF or CRLF, each one break; the empty text after a final line break is not a line; a leading UTF-8 byte-order mark is part of the first line.

The link's reported line range is the first and last content line (line mode) or the sentinel line (same-line mode). A line-mode region with no lines between its sentinels is reported at the line after the start sentinel, as that line to that line. When the only lines between the sentinels are other sentinel lines, the range covers those lines.

Rules:

```text
content between the sentinels                          -> valid
no content, or only blank lines, between the sentinels -> valid + WARNING: empty marker region
same-line region whose content is only whitespace      -> valid + WARNING: empty marker region
```

"Blank" and "whitespace" mean only TAB, LF, VT, FF, CR and SPACE (the set chapter 11 §15 names). Comment decoration counts as content: `/* @use-case:a#b */ /* @use-case:end a#b */` holds ` */ /* ` and is not empty.

The warning reads `<file>:<line>: empty marker region: <id>`, naming the first line of the reported range.

An emptied region usually means the code it marked has moved, as in a refactor that moved it into a new file, leaving the markers behind. The warning is shown wherever people look: `validate`, `links`, and `status`, in its list and in the use case's detail (chapter 16 §9). It is a warning, not INVALID: a region can be empty for a moment mid-refactor.

## Marker region content

Marker sentinels themselves are not part of the linked content.

```text
opening sentinel line
      |
      v
[ fingerprinted linked content ]
      |
closing sentinel line
```

Changing decoration around the sentinel does not change the linked content.

## Multiple marker regions

One marker identity may resolve to multiple regions.

The resolved set is ordered deterministically by:

```text
repo-relative file path
then start position
```

Filesystem traversal order never affects identity or freshness.

Two regions containing identical content are still two distinct regions.

Adding/removing/changing any resolved region changes the resolved linked-content set.

## Marker search boundary

Markers are searched across the whole workspace.

They are not restricted to the use case's scope or `use_cases_dir`.

However, marker search explicitly ignores all Use Cases-owned content:

```text
every use-cases.yml
use-case-groups.yml
use-cases-bridge.yml
all discovered use-case definition YAML
.use-cases/**
```

This prevents recursion and false markers from examples/config/results.

Marker search never leaves the workspace root.

Symlinks are never followed (chapter 04), so a marker cannot be found behind one and nothing escapes the workspace through one.

Every file that is not excluded is read, and how the scan treats unreadable files, special files and odd names is chapter 09 §20.3.

# Manual bindings

## Manual binding object

Only manual bindings are written in YAML.

```text
id       1
kind     1   always "manual"
locator  1
```

Range example:

```yaml
- id: legacy-login
  kind: manual
  locator:
    file: src/login.py
    start:
      line: 40
    end:
      line: 78
```

Whole-file example:

```yaml
- id: auth-config
  kind: manual
  locator:
    file: config/auth.yml
```

Locator shape:

```text
file   1
start  0..1
end    0..1
```

`start` and `end` are both present or both absent.

Position:

```text
line    required
column  optional
```

Positions are:

```text
1-based
inclusive
```

Columns count Unicode code points from 1. A leading byte-order mark is not a column.

```text
start column   1 .. line length + 1
end column     1 .. line length
```

On one line, an end column one less than the start column is an empty range. An end column on an empty line is INVALID.

A link that covers a whole file reports lines 1 to the last line holding any bytes; an empty file is 1 to 1. Line counting is that of "The linked region".

All file paths are workspace-root-relative.

Whole-file bindings may target text or binary files.

Range bindings are text-only.

## Manual binding validity

Invalid:

- missing file
- path escaping workspace root
- malformed range
- range outside file
- invalid line/column positions
- `kind` other than `manual`

A missing manual file is INVALID.

An empty but valid manual range (an end column one less than the start column, on one line) is allowed with a warning.

A whole-file binding to an empty file is valid with a warning.

# Rules for every link

## Overlap

Overlap is allowed, whatever the sources of the links.

Two links of the same use case and the same role (implementation, or the same route's validation) whose byte spans intersect emit:

```text
WARNING: redundant overlapping links
```

Overlap between different use cases or different roles is normal and says nothing.

Warnings do not block READY.

## Symlinks

A symlink is never followed (chapter 04). A binding to one tracks its target text, wherever it points.

## Excluded content

Use Cases has no Git model.

A link (a manual binding) may point into a path that discovery excludes: a built-in exclusion or `discovery.exclude` (chapter 04).

That is:

```text
allowed
+
WARNING: the link points at excluded content
```

The warning is the same on every system.

## Diagnostics

Diagnostics are orthogonal to authored state.

```text
State
  INVALID / DRAFT / READY

Diagnostics
  errors / warnings
```

Warnings never block READY.

Example:

```text
READY + 2 warnings
```

is valid.

Every marker outcome, in one table:

| Found in the code | Result |
|---|---|
| a well-formed pair for a known use case and route | a link |
| a well-paired marker for an unknown use case or route | WARNING; no link |
| a malformed marker id | WARNING; ignored |
| an empty region | WARNING; a link with empty content |
| a file that is not strict UTF-8 | WARNING: unsupported-text; no links from that file |
| an end with no start, a start never closed, crossing pairs, a marker nested in itself (for any use case, known or not) | INVALID |
| one binding identity from two sources | INVALID |
| the same binding twice on one line (one link key, two regions) | INVALID |
| a marker behind a symlink | never seen: symlinks are not followed (chapter 04) |

Warnings keep the workspace valid because code may run ahead of its use cases. INVALID means the core cannot read the links safely, so nothing is judged until it is fixed.

## Binding stability

Binding ID is stable identity, whether it comes from a marker or a manual binding.

Renaming a binding ID is not an ordinary edit:

```text
old link removed
+
new link created
```

Previous verification does not automatically transfer across the rename.

## Freshness identity

Freshness asks:

```text
Does an old validation result still apply
to the current use case?
```

Repository-level config controls what part of a link participates in freshness.

```yaml
freshness:
  binding_identity: content
```

Allowed values:

```text
content
content-and-locator
```

If omitted:

```text
binding_identity = content
```

### `content` — default

The resolved linked content is the freshness identity.

```text
same binding ID
+
same resolved linked content
+
different file/range/marker location
        |
        v
still fresh
```

The locator must still resolve validly.

Moving lines, files, or marker occurrences alone does not stale prior verification when the same link still resolves to the same content.

### `content-and-locator` — strict

The locator also participates in freshness.

```text
same linked content
+
different file/range/marker location
        |
        v
stale
```

## Freshness normalization

Exact content comparison is the default.

Root config may optionally normalize content before fingerprinting:

```yaml
freshness:
  binding_identity: content

  normalization:
    ignore:
      - line-endings
      - whitespace
```

If `normalization` is omitted, it is equivalent to:

```yaml
normalization:
  ignore: [line-endings]
```

Meaning:

```text
every content change matters, except CR/LF line-ending style
```

so an LF and a CRLF checkout of the same commit agree. Write `ignore: []` for exact bytes.

Initial language-agnostic normalizations:

```text
line-endings
whitespace
```

No generic `comments` normalization exists because identifying comments requires understanding the language.

Normalization is explicit opt-in sugar around freshness comparison; it never changes the authored link itself.

## Text encoding

Marker scanning reads strict UTF-8. A leading byte-order mark is allowed and belongs to the first line.

```text
file holds "@use-case:" but is not strict UTF-8   -> WARNING: unsupported-text; its markers resolve to no link
file starts with a UTF-16 or UTF-32 byte-order mark -> WARNING; its markers cannot be read
```

The scan looks for the bytes `@use-case:` before it decodes anything. The unsupported-text check runs only on a file that holds them, so a file without them is never warned about for its encoding. A UTF-16 or UTF-32 byte-order mark is the exception: such a file can never hold those bytes as written, so it is always warned about, once.

The core never guesses an encoding or silently reinterprets bytes.

Manual whole-file bindings may still bind binary content.

## Core principle

```text
Binding ID = stable identity (from a marker or a manual binding)
Locator    = how the linked region is found
Content    = what freshness watches by default
```

Exact fingerprint/hash implementation is defined in `11 — Fingerprints + Freshness`.
