# ADR 023: The gate blocks anything that stopped being proven

## Status

Accepted - 2026-09-27

## Context

CI needs one yes-or-no answer: may this change merge? Chapter 03 said a group's gate asks "is every use case verified?". Applied to a whole repository, that blocks every pull request that adds a use case before its tests exist, or whose tests are legitimately skipped on one platform, and teams adopting Use Cases gradually would switch it off.

Letting anything but `failed` through is too loose. A stale verdict means the code changed since the use case was proven, and a gate exists to catch exactly that. The owner asked why stale should not block, and it should: a hand-checked route that would go stale on every change is marked `gates_verification: false`, and then it never blocks.

## Decision

`use-cases status --gate` exits 1 when anything blocks, for the workspace or one group:

| Use case status | Default | `--strict` |
|---|---|---|
| failed | blocks | blocks |
| error | blocks | blocks |
| stale | blocks | blocks |
| incomplete | warns | blocks |
| unverified | warns | blocks |
| verified | passes | passes |

- An INVALID workspace blocks (exit 2).
- A use case's status is the worst of its gating routes (chapter 07). A route with `gates_verification: false` never blocks.
- DRAFT use cases never block, in either mode.
- `--gate` cannot be combined with `--state` or a use case argument: it considers every use case in its scope.

## Consequences

- Good: nothing that was proven can quietly stop being proven, while new and legitimately skipped work still merges.
- Good: `--strict` (for example on a release group) gives "everything must be proven" when a team wants it.
- Cost: any code change to a use case's linked code blocks until it is verified again, so CI must run `verify` before the gate.
- Cost: a hand-checked gating route must be re-recorded after every change to its code, or marked non-gating.

## Considered Options

- **Only `failed` blocks:** easiest to adopt, but a stale use case, whose proof no longer applies, would merge unseen.
- **Everything must be verified by default:** strongest, but it punishes adding use cases before their tests, and teams would disable it.

## Confirmation

These acceptance tests pin the rule:
- `test_the_default_gate_blocks_failed_error_and_stale_and_warns_on_the_rest`
- `test_strict_blocks_everything_not_verified_but_never_a_draft`
- `test_each_status_on_its_own`, `test_stale_alone_blocks`, `test_a_failing_non_gating_route_never_blocks`
- `test_an_invalid_workspace_blocks_with_exit_2`, `test_a_group_is_gated_on_its_members_only`

## Related Links

- `docs/design/16-cli-surface.md` §10
- `docs/design/03-use-case-groups.md`, `docs/design/07-verification-state-model.md`
