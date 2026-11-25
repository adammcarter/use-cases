# ADR 032: Sign-off is recorded on the use case, pinned to its promise, and gated by tier

## Status

Accepted - 2026-10-11

## Context

The owner's rule: the value tier sets the sign-off level. Critical behaviour always needs a person; lower tiers an agent may handle if it asks first. A survey of sessions using today's plugin (`docs/research/plugin-survey.md`) found approvals were never recorded, use cases were edited after approval with nothing to show it, and owners approve both before the code and by trying the build.

## Decision

- **Two moments, the tier decides who:** before the code (the proposal) and after seeing it (the build). Critical: the person, always, at both. Core: the person by default. Supporting: an agent, where the person has said it may, asked once.
- **The sign-off before the code is recorded on the use case** as `approved` (who, the day, and a fingerprint of the promise: id, title, description, value tier, intent, scenarios, out of scope). It is written only by `use-cases approve` or `apply --approved-by`, never by hand or by `save`, and a save keeps the approval the use case had.
- **A changed promise reads `changed since approved`.** Changing how a use case is proven (routes, tests, links) keeps the approval.
- **The gate, per repo:** with `sign_off: required` (root only), a READY use case not approved as it reads now is held: critical blocks, core and supporting warn, `--strict` blocks all; drafts never. Without it, approvals are recorded and shown, never gating. `approve --all` catches a repo up in one commit.
- **The sign-off after seeing it** is a verdict on a route someone performs; what it must show is chapter 23's.

## Consequences

- Good: "critical always needs you" is enforced, not just advised, wherever a repo turns it on.
- Good: an edit after approval can no longer pass unnoticed.
- Good: approvals travel with the use cases, in the same commits, reviewed the same way.
- Cost: the record says who approved but cannot prove a person typed the name; that is checked where the commit is reviewed.
- Cost: what changed since an approval is read from version history, not from the core.

## Considered Options

- **Approvals in the results store:** never committed, so lost on every fresh checkout; a decision is not a test result.
- **Approval of the whole file or the whole use case:** any edit, even to a test route, would reset it and teach people to ignore it.
- **Always on:** every critical use case in an adopting repo would block on the first day.

## Confirmation

- `test_signoff.py`: an approval recorded on the use case; each kind of promise change reading changed, a change to how it is proven not; `--all` and its rules; a dry run writing nothing; save never writing an approval and keeping the one it had; a signed-off batch approving what it saves; the gate without sign_off, and with it per tier, strict and drafts; a changed critical promise blocking until approved again; what people see; sign_off root only.
- `test_mcp.py`: a sign-off through the tool, `by` required.

## Related Links

- `docs/design/21-agent-workflows.md` §6
- `docs/design/16-cli-surface.md` §10, §14
- `docs/design/02-use-case-schema.md` (`approved`), `docs/design/04-workspace-structure.md` (`sign_off`)
- ADR 023 (the gate), ADR 031 (batches)
