# 02 — Minimal Use-Case Schema

This document defines the canonical authored use-case object.

## Core shape

```text
Use case
  |
  +-- identity
  +-- human description
  +-- behaviour
  +-- validation routes
  +-- implementation bindings   (optional)
```

A use case names no command, runner or test tool. It may point at repository files through optional manual bindings and resources.

## Canonical example

```yaml
id: authenticate
title: Authenticate user
description: Handles authentication through the main login surface.
value_tier: core

intent: Allow a valid user to authenticate and reach the dashboard.

out_of_scope:
  - Social login.
  - Password reset.

scenarios:
  - id: valid-credentials
    given:
      - The user is signed out.
      - The account exists.
    when:
      - The user submits valid credentials.
    then:
      - An authenticated session is created.
      - The dashboard is shown.

validation:
  - id: unit-tests
    type:
      kind: unit
    covers:
      - valid-credentials
    resources:
      - kind: file
        path: fixtures/users.json

  - id: manual-login-check
    type:
      kind: acceptance
    covers:
      - valid-credentials
    gates_verification: false
    procedure:
      setup:
        - Launch the app signed out.
      steps:
        - Enter valid credentials.
        - Submit.
        - Observe the dashboard.

bindings:
  - id: legacy-login
    kind: manual
    locator:
      file: src/login.py
      start:
        line: 40
      end:
        line: 78
```

The `unit-tests` route has no binding in YAML. Its tests carry markers in the code. Markers use the resolved ID, here `app.auth.login.authenticate`, which the local `id` gains from its scope and file prefixes (`04 — Workspace Structure`):

```text
// @use-case:app.auth.login.authenticate#unit-tests.valid-credentials
@Test func validCredentialsAuthenticate() { … }
// @use-case:end app.auth.login.authenticate#unit-tests.valid-credentials
```

## What stays in a use case

```text
 KEPT — behaviour and how it's proved         LIVES ELSEWHERE — how it runs
 ────────────────────────────────────         ──────────────────────────────────────
 id, title, description, value_tier           how to start the tests
 intent, out_of_scope                            → run command in use-cases-bridge.yml
 scenarios (given / when / then)              how a test report becomes results
 validation routes:                              → results transformer (helper)
   type, covers, gates_verification           markers around tests and code
   procedure (plain-language manual steps)       → in the code itself, no YAML entry
 optional links from the YAML:
   bindings   manual file / line references
   resources  fixtures, schemas, golden files
```

| Field | Where | Why it is here |
|---|---|---|
| `procedure` | route | Plain-language steps are part of how the behaviour is proved |
| `bindings` | use case, route | Optional: point at code without touching it |
| `resources` | route | Optional: data files whose changes should stale the route |

Nothing in a use case says how tests are started or how their output is read. Those are helpers, defined in chapters 10, 13 and 14.

## Authored state

```text
INVALID
   |
   v
DRAFT
   |
   v
READY
```

### INVALID

Cannot be safely interpreted.

Examples:

- malformed YAML, a duplicate key, a plain value two YAML versions read differently, or unquoted text followed by a comment on its line (chapter 09 §14)
- malformed IDs
- duplicate resolved IDs, or two scenarios or two routes with one ID in the same use case
- broken references
- invalid binding or resource locators
- structurally invalid fields, or a value of the wrong type

INVALID is found per file and per use case, and it blocks the whole workspace: nothing is judged until it is fixed, because a model assembled around an unreadable file could quietly lose use cases.

### DRAFT

Structurally interpretable but not yet fully written.

A draft may be missing:

- complete behaviour
- complete validation

Minimum useful draft:

```yaml
id: success
title: Successful login
```

### READY

```text
READY = fully written
```

A READY use case requires:

```text
identity
+
title
+
value_tier
+
intent
+
1..N scenarios
+
1..N validation routes
+
every scenario covered by >= 1 gating route
```

Links are never required for READY. A use case with no links is still READY; it can be verified with `use-cases record`, and freshness then tracks only its own wording.

Warnings, which never block READY:

```text
use case has no implementation links
  -> freshness will not track its code

gating route has no validation links and no procedure
  -> only `use-cases record` can verify it
```

```text
READY + warnings
```

is valid.

## Fields

### `id`

```text
required: yes
cardinality: 1
```

Identity grammar is defined in `05 — Identity & ID Grammar`.

### `title`

```text
required: yes
cardinality: 1
```

```text
id    = machine identity
title = human identity
```

### `description`

```text
required: no
cardinality: 0..1
```

### `value_tier`

```text
DRAFT: optional
READY: required
```

Ordered values:

```text
critical
core
supporting
```

### `intent`

```text
DRAFT: optional
READY: required
```

```text
title  = what this behaviour is called
intent = why this behaviour exists
```

### `out_of_scope`

```text
required: no
cardinality: 0..N
```

### `scenarios`

```text
DRAFT: 0..N
READY: 1..N
```

Each scenario:

```text
id      1
given   0..N
when    1..N
then    1..N
```

Scenario IDs are unique within their use case, and so are route IDs. Binding IDs never imply a scenario: a binding named like a scenario means nothing by that.

Authoring notes:

- Quote a key or value that YAML might read as something other than text. `on`, `No`, `yes`, `1:30`, `2024-01-01` and `1e3` unquoted are INVALID, because YAML 1.1 and 1.2 read them differently (chapter 09 §14). `title: "No"` and `"on": "2026-10-11"` are fine.
- Quote text that contains ` #`. Unquoted, YAML reads it as the start of a comment: `- Check medal #4 shows` would be cut to `Check medal`, so it is INVALID. Write `- "Check medal #4 shows"`, and put comments on their own line.
- In YAML's inline list form, a comma splits one sentence into several steps. `when: [Two values are pushed, then popped.]` becomes two steps. Use the block list form (one `- ` item per line), or quote any sentence that contains a comma. The schema catches a split that produces a number, such as `5,400,000`, but not a split between words.

### `validation`

```text
DRAFT: 0..N
READY: 1..N
```

Each route follows `06 — Validation Model`.

Route shape:

```text
id                  1
type                1
covers              1..N
gates_verification  0..1 (default: true)
procedure           0..1
bindings            0..N   manual validation bindings
resources           0..N
```

For READY:

```text
every scenario
    |
    +-- covered by >= 1 gating route
```

### top-level `bindings`

Top-level bindings are manual implementation bindings.

```text
cardinality: 0..N (DRAFT and READY)
```

Validation bindings live inside their validation route.

```text
use_case.bindings[]     = implementation
validation[].bindings[] = route validation
```

Only manual bindings are written in YAML. Markers are found in the code and need no entry. Link details are defined in `08 — Links: markers and manual bindings`.

### `approved`

The sign-off of the use case's promise (chapter 21): who approved it, on which day, and a fingerprint of its words then. The day is a real calendar date, `YYYY-MM-DD`: `2026-02-30` is INVALID.

```yaml
approved:
  by: Sam
  "on": "2026-10-11"
  # the fingerprint: 64 hex digits
  behaviour: 3f9a…
```

```text
cardinality: 0..1 (DRAFT and READY)
written by:  use-cases approve, or apply --approved-by; never by hand, never by save
```

The promise is the id, title, description, value tier, intent, scenarios and out of scope. Its fingerprint is computed as chapter 11 §89.9 says. How the use case is proven (its validation routes and bindings) is not part of it, so changing them keeps the approval. A later change to the promise leaves the record in place but no longer matching: the use case reads `changed since approved` until it is approved again.

## Runtime status

Only READY use cases have runtime verification sub-status.

```text
INVALID
DRAFT
READY
  |
  +-- verified
  +-- stale
  +-- unverified
  +-- incomplete
  +-- error
  +-- failed
```

The status model is defined in `07 — Verification State Model`.

## Not stored here

Do not author runtime state or run configuration in use-case YAML. The one record the core writes into a use case is its sign-off (`approved`): a decision about the promise, kept with it and reviewed with it, not runtime state.

Not stored here:

- verification status
- validation results
- run timestamps
- evidence history
- caches
- group membership
- commands, runners, test tools, report paths

## Canonical model vs sugar

This explicit shape is canonical.

Future templates, aliases, or agent tooling may reduce repetition, but must resolve to this same model.
