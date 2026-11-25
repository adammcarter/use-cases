# 07 — Verification State Model

## State hierarchy

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

Examples in this chapter use a small Swift project. Nothing in the rules depends on it: the shapes are the same for any language and tool.

## Authored state

Authored state answers:

```text
Is this use case fully written?
```

### INVALID

Cannot be safely interpreted.

### DRAFT

Interpretable, but incomplete.

A DRAFT may still be in behaviour design, validation design, or RED/GREEN implementation.

### READY

Fully written.

```text
READY = ready for verification
```

A READY use case has:

- complete behaviour
- complete validation
- every scenario covered by at least one gating validation route

Links are never required for READY. A READY use case with no links is verified with `use-cases record`, and its freshness tracks only its own wording.

Only READY use cases have runtime verification sub-status.

## How the core judges

Results arrive from two sources: a results transformer reading a test report, or `use-cases record`. Either way, only the core judges.

```text
 transformer says                which link?                 every link heard?
 "LoginTests.swift line 6   ──▶  valid-credentials,     ──▶  every validation link of
  passed"                        lines 5–7                   the route needs a result
                                                                     │
                                                                     ▼
 use case                        route                        worst result wins
 worst of its gating       ◀──   verdict for this        ◀──  fail > error >
 routes                          fingerprint                  incomplete > pass
```

What happened, and what the core says:

| What happened | What the core says |
|---|---|
| Every validation link got results, and all passed | `verified` |
| Any result failed | `failed` — even if another link of the route didn't run |
| A validation link got no result | no verdict: "its test didn't run" — never a pass |
| A test was skipped | `incomplete` |
| A test sits inside no link | reported as "test not tied to a use case" |
| Linked code, a linked test, a resource or the intent changed later | `stale` |
| Only the title changed, or code moved without changing | still `verified` |
| Linked code, a linked test, a resource or the use case changed between the start point and the finish point | no verdict: "code changed during the run" |
| The build broke, or a transformer broke | run error — no route is marked `failed` |

Rules:

- **Every validation link needs a result.** A route with a link that received no result gets no verdict, with the diagnostic "its test didn't run". A filter or command that runs nothing can never verify anything.
- **A fail beats "didn't run".** If any link of the route failed, the route is `failed`, because the behaviour is already known to be broken.
- **Worst wins.** Otherwise the route takes the worst of its link results: `fail` > `error` > `incomplete` > `pass`.
- **Implementation links and resources never expect results.** They feed freshness only.
- **Run errors never fail a route.** A command that exits non-zero with no failing result (such as a build failure), a missing report, or a broken transformer is recorded as a run error. No route gets a verdict from it.
- **Recorded verdicts need no links.** `use-cases record` gives a route a verdict directly, fingerprinted against the current workspace.

The judging flow is defined in `13 — Verify flow`.

## Route verification status

Each validation route derives one status:

- `verified` — current applicable result is `pass`.
- `stale` — a previous result exists but no longer matches current inputs.
- `unverified` — no applicable current result exists.
- `incomplete` — validation did not reach a verdict.
- `error` — validation mechanism failed.
- `failed` — validation completed and expected behaviour was not satisfied.

```text
No result          -> unverified
Fingerprint stale  -> stale
Current pass       -> verified
Current incomplete -> incomplete
Current error      -> error
Current fail       -> failed
```

A run that gives a route no verdict ("its test didn't run", "code changed during the run") adds no evidence. The route's status still comes from existing evidence for its current fingerprint: usually `unverified` or `stale`, and `verified` only if an earlier run already passed this exact state. A route's diagnostic is shown only when no result matches its current fingerprint (chapter 12 §27); a route an earlier run already verified in this exact state shows none.

For storage purposes, "result" means a committed result from a valid sealed run in the root `.use-cases/runs/` history. An unsealed active or interrupted run never supplies partial current evidence. A sealed run with interrupted termination may supply the results it committed; omitted routes get no verdict.

## Best-to-worst order

```text
BEST
verified
stale
unverified
incomplete
error
failed
WORST
```

`failed` is worse than `error` because:

```text
error  = behaviour could not be determined
failed = behaviour was determined not to work
```

## Overall READY status

Only routes with:

```yaml
gates_verification: true
```

participate in the overall use-case verification status.

The use case shows the worst status among its gating routes.

```text
unit         -> verified
integration  -> stale
acceptance   -> verified
                   |
                   v
use case     -> stale
```

Non-gating routes retain their own status but cannot lower the overall use-case status.

## Derived, never authored

```text
definitions
+ links
+ current content
+ validation results
        |
        v
    core judges
        |
        v
 derived state
```
