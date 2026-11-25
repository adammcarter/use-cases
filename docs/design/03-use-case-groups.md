# 03 — Use-Case Groups Schema

Use-case groups define named subsets of resolved use cases.

They are optional and live outside the core use-case schema.

```text
resolved use cases
      |
      v
use-case-groups.yml
      |
include / exclude selectors
      |
      v
named unordered subset
```

## File

```text
use-case-groups.yml
```

The file is optional.

```text
file absent
  -> valid workspace
```

If the file exists, it must validate.

## File envelope

```yaml
schema_version: 1

groups: {}
```

Rules:

```text
schema_version   1
groups           required
group entries    0..N
```

`groups: {}` is valid with a warning.

Unknown fields are invalid.

Duplicate YAML keys are invalid.

## Schema version

```yaml
schema_version: 1
```

Rules:

- positive integer
- `1` is the current schema
- backward-compatible additions remain schema version `1`
- a breaking schema change requires a new major schema version
- an unsupported higher version is invalid for a tool that cannot understand it

## Group names

Group names use the standard single-segment ID grammar.

Valid:

```text
ci
smoke
release
bob
group-a
nightly-2
```

Invalid:

```text
CI
group a
group/a
group.one
```

Group names are stable identifiers for the group.

Renaming a group does not affect use-case freshness.

## Group shape

Example:

```yaml
groups:
  smoke:
    description: Fast critical-path checks.

    include:
      ids:
        - app.login.success

      prefixes:
        - app.auth

      globs:
        - app.*.success

    exclude:
      ids:
        - app.auth.legacy-login
```

Each group has:

```text
description   0..1
include       0..1
exclude       0..1
```

The group name is the mapping key.

## Description

`description` is human-facing metadata only.

It does not affect membership or freshness.

## Selectors

Both `include` and `exclude` use the same explicit object shape.

```text
ids       0..N
prefixes  0..N
globs     0..N
```

No shorthand selector lists are used.

Example:

```yaml
include:
  ids:
    - app.checkout.complete

  prefixes:
    - app.auth

  globs:
    - app.*.success
```

Selectors always operate on fully resolved use-case IDs.

Local IDs such as:

```text
success
```

are not valid selectors.

## Exact IDs

Exact IDs select one fully resolved use-case ID.

Example:

```yaml
ids:
  - app.auth.login.success
```

If an exact ID does not exist:

```text
INVALID
```

This applies equally to `include` and `exclude`.

## Prefixes

Prefixes use namespace-aware matching.

Example:

```yaml
prefixes:
  - app.auth
```

Matches:

```text
app.auth
app.auth.login
app.auth.login.success
```

Does not match:

```text
app.authentication
app.author
```

A prefix that matches nothing:

```text
valid + WARNING
```

## Globs

Globs operate on whole ID segments only.

Grammar:

```text
*   = exactly one whole ID segment
**  = zero or more whole ID segments
```

`**` also matches zero segments at the end, so `app.checkout.**` includes `app.checkout` itself, just as the path pattern `build/**` matches `build` (chapter 04).

Examples:

```text
app.*.success
app.**
**.critical
```

Valid matches:

```text
app.*.success
  -> app.login.success
  -> app.checkout.success
```

Not matched:

```text
app.success
app.auth.login.success
```

Character-fragment globs are not supported.

Invalid:

```text
app.log*
app.*login
app.**foo
```

A malformed glob is invalid.

A valid glob that matches nothing:

```text
valid + WARNING
```

## Selector syntax

Selectors follow the standard ID grammar.

```text
ids      -> full resolved IDs
prefixes -> valid namespaces
globs    -> valid namespace-glob grammar
```

Malformed selectors are invalid.

## Include / exclude resolution

Resolution is deterministic:

```text
include omitted
      |
      v
start with all resolvable use cases (an include that selects nothing is INVALID)

include present
      |
      v
start with include matches

      then

exclude matches
      |
      v
subtract them
```

`exclude` always wins.

Overlap between include and exclude is valid and expected.

No warning is emitted for include/exclude overlap.

## Empty selector objects

Examples:

```yaml
include: {}
exclude: {}
```

`exclude: {}` is valid but redundant (a warning). An `include` that selects nothing, `include: {}` or `include: { ids: [] }`, is INVALID: it would otherwise quietly mean "every use case", and a gate would widen without anyone noticing. Leave `include` out to mean every use case.

```text
exclude: {}   -> valid + WARNING
include: {}   -> INVALID
```

Semantics:

```text
include omitted
  -> start with all use cases

exclude omitted / exclude {}
  -> subtract nothing
```

## Empty selector arrays

Example:

```yaml
exclude:
  ids: []
```

Valid but redundant:

```text
valid + WARNING
```

The same applies to empty `prefixes` and `globs` arrays. An `include` whose arrays are all empty selects nothing and is INVALID, as above.

## Duplicate selectors

Literal duplicates within the same selector list are valid but warn.

Example:

```yaml
ids:
  - app.login.success
  - app.login.success
```

Result:

```text
valid
+
WARNING: duplicate selector
```

The same rule applies to duplicate prefixes and duplicate globs.

Resolution deduplicates them.

## Overlapping selectors

Overlap across different selector kinds is valid and does not warn.

Example:

```yaml
include:
  ids:
    - app.login.success

  prefixes:
    - app.login
```

Broad + specific selection is considered normal.

Resolved membership is always deduplicated.

## Dynamic membership

Exact-ID selectors are fixed.

Prefix and glob selectors are dynamic.

Example:

```text
prefix: app.auth
      |
new use case added:
app.auth.reset-password
      |
      v
automatically joins the group
```

Membership is always derived from the current resolved use-case set.

Resolved members are never stored back into `use-case-groups.yml`.

Group membership does not affect use-case freshness.

## Empty resolved group

A group may resolve to zero use cases.

```text
valid + WARNING
```

This includes cases where exclusions remove every included use case.

## DRAFT and READY membership

Groups may select:

```text
DRAFT
READY
```

Invalid use cases cannot participate in resolved membership because their identity or structure cannot be safely trusted.

The groups file itself may still be structurally validated even when use-case resolution is blocked elsewhere.

## Whole-use-case selection only

Groups select whole use cases.

They do not select individual validation routes in v1.

```text
Group = WHICH use cases belong together
```

Groups select use cases for status views and gates (chapter 16), for example `use-cases status --group smoke --gate`: does anything in `smoke` block?

Groups never choose commands. What runs is set by the run commands in `use-cases-bridge.yml` (`14 — Run commands`); groups only filter which use cases are reported or gated.

## No group composition in v1

Groups cannot include other groups.

Not supported:

```yaml
include:
  groups:
    - smoke
```

This avoids cycles and keeps membership easy to understand.

## Groups are unordered

A group is an unordered set.

The order selectors or resolved members appear in does not affect meaning.

## One root groups file in v1

v1 supports one optional root-level:

```text
use-case-groups.yml
```

Nested group files are not part of v1.

Because selectors use fully resolved IDs, one root groups file can select use cases across the entire repository.

## Diagnostics

Groups follow the general diagnostic model:

```text
INVALID
  -> malformed or unsafe configuration

WARNING
  -> valid but suspicious/redundant configuration
```

Examples of warnings:

- `groups: {}`
- empty selector objects
- empty selector arrays
- duplicate literal selectors
- prefix matches nothing
- glob matches nothing
- resolved group is empty

Warnings do not make the groups file invalid.

## Separation of concerns

```text
02 = what a use case is
03 = how resolved use cases are grouped
04 = workspace/repository structure
```

Groups consume resolved use cases.

The core use-case schema does not contain group membership.
