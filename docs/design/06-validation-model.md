# 06 — Validation Model

## Validation route

A validation route says how a behaviour is proved. It never says how tests are started or how their output is read.

```text
validation route
   |
   +-- id
   +-- type
   +-- covers
   +-- gates_verification
   +-- procedure     0..1  plain-language steps
   +-- bindings      0..N  manual validation bindings
   +-- resources     0..N  freshness-only inputs
```

Example:

```yaml
validation:
  - id: unit-tests
    type:
      kind: unit
    covers:
      - valid-credentials
      - invalid-password
    resources:
      - kind: file
        path: Packages/Auth/Fixtures/users.json

  - id: manual-login-check
    type:
      kind: acceptance
    covers:
      - valid-credentials
    gates_verification: false
    procedure:
      setup:
        - Launch the app in a signed-out state.
      steps:
        - Perform the valid-credentials scenario.
      reset:
        - Return the app to the signed-out state.
```

## What a route carries, and what it doesn't

```text
 ON THE ROUTE (how it's proved)          ELSEWHERE (how it runs)
 type        unit, acceptance, …          run command      use-cases-bridge.yml
 covers      which scenarios              transformer      use-cases-bridge.yml
 gating      does it block the use case   markers          in the test code
 procedure   plain-language steps
 bindings    optional file / line links
 resources   optional fixtures, schemas
```

A route stays the same whatever language, test framework or command proves it.

## Type

`type` classifies coverage only.

Built-ins:

```text
unit
integration
contract
snapshot
ui
e2e
acceptance
performance
```

Shape:

```yaml
type:
  kind: unit
```

Custom:

```yaml
type:
  kind: custom
  name: accessibility
```

## Coverage

```yaml
covers:
  - valid-credentials
```

Rules:

```text
covers              1..N
referenced scenario must exist
```

For READY, every scenario must be covered by at least one gating route.

## Verification gate

```text
gates_verification: true
  -> route counts towards the use case's overall status

gates_verification: false
  -> non-blocking route
```

`gates_verification` defaults to `true`, so `gates_verification: false` is only needed for explicitly non-blocking validation.

## Procedure

A procedure is plain-language instructions for performing the validation.

```yaml
procedure:
  setup:
    - Launch the app signed out.
  steps:
    - Enter valid credentials.
    - Submit.
    - Observe.
  reset:
    - Restore initial state.
```

Shape:

```text
setup  0..N
steps  1..N
reset  0..N
```

- The performer is anyone: a human, agent, automation, or future actor. Who performs it is runtime context, never authored.
- Covered scenario `then` outcomes are the expected results by default.
- One procedure may cover several scenarios.
- A route may have both a procedure and validation links: the procedure says how to check it by hand, and the links receive automatic results from the verify flow, exactly as for a route without a procedure. A procedure route with no validation links gets verdicts only from `use-cases record`.

### Procedural verdict boundary

Displaying or attempting the steps never implies success.

A verdict must be recorded explicitly with `use-cases record`:

```text
pass
fail
incomplete
error
```

## Validation links

A route's validation links sit around the tests that prove it. They come from:

- markers in the test code: `@use-case:<use-case-id>#<route-id>.<binding-id>`
- manual bindings on the route, in the YAML
- link transformers configured in `use-cases-bridge.yml`

```yaml
bindings:
  - id: integration-script
    kind: manual
    locator:
      file: tests/python/test_login_integration.py
```

Every validation link expects a result when tests run. A link that gets none means its test didn't run, and the route gets no verdict (`07 — Verification State Model`).

Validation links are optional. A gating route with no validation links and no procedure can only be verified with `use-cases record`, and produces a warning.

Link details are defined in `08 — Links: markers and manual bindings`.

## Universal result contract

```text
status   1
message  0..1
```

Status:

```text
pass
fail
incomplete
error
```

```text
pass       = expected behaviour was shown
fail       = expected behaviour was shown not to hold
incomplete = validation did not reach a verdict (e.g. a skipped test)
error      = the validation mechanism failed
```

Every source of results — a transformer reading a test report, or a person or agent using `use-cases record` — speaks this one contract.

## Persisted result identity

Minimum conceptual record:

```text
use_case     1
route        1
status       1
message      0..1
fingerprint  1
via          1..N   which validations, or "record"
recorded_at  1
```

Results live in sealed run folders under `.use-cases/runs/` as defined in `12 — Results Storage`. Excluding `.use-cases/` from source control is recommended; the core has no Git integration.

## Resources

Resources are extra repository material affecting route freshness but not already represented by links.

Examples:

```text
fixtures
schemas
snapshots
test data
configuration
golden files
generated reference data
```

Resources belong to validation routes only. They never expect results.

Initial kinds:

```text
file
glob
```

Example:

```yaml
resources:
  - kind: file
    path: fixtures/users.json

  - kind: glob
    pattern: schemas/**/*.json
```

Rules:

- repo-root-relative
- missing file -> invalid
- the pattern uses chapter 04's path pattern dialect
- malformed glob -> invalid
- zero-match glob -> invalid
- one-or-more match glob -> valid

## Route fingerprint

A route fingerprint includes:

```text
intent
+
covered scenarios
+
route definition
  id
  type
  covers
  gates_verification
  procedure
+
implementation link content
+
this route's validation link content
+
this route's resource contents
+
freshness policy
```

Binding locator identity is controlled by repo config:

```yaml
freshness:
  binding_identity: content
```

### Default: `content`

```text
same linked content
different file/range/marker location
        |
        v
fresh
```

### Strict: `content-and-locator`

```text
same linked content
different locator
        |
        v
stale
```

Not freshness-sensitive in either mode:

```text
title
description
out_of_scope
comments
formatting
definition YAML file path
timestamps
previous results
bridge settings, run commands, transformers
```

Freshness rules:

```text
implementation link content changes
  -> every route of the use case stale
  -> use case stale

intent changes
  -> all routes stale

validation type changes
  -> route stale
  -> if gating, use case stale

gates_verification changes
  -> recompute route + use case

covers changes
  -> route stale
  -> if gating, use case stale

procedure changes
  -> route stale
  -> if gating, use case stale

resource content changes
  -> route stale
  -> if gating, use case stale

validation link content changes
  -> route stale
  -> if gating, use case stale

non-gating route changes
  -> that route stale only
```

Exact hashing and canonicalisation are defined in `11 — Fingerprints + Freshness`.

## Where running lives

A route never carries execution configuration. There are no fields such as:

```text
command
arguments
environment
timeout
retries
parallel
batch
```

How tests are started (`14 — Run commands`), how their reports become results (`10 — Bridge settings + transformer contract`), and how results are judged (`13 — Verify flow`, `07 — Verification State Model`) are all outside the route.
