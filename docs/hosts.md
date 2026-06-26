# Host Support

Presentation Skills treats Claude, Codex, Copilot, and OpenCode as first-class
host families, but profile existence is not proof of support.

| Host | Profile | Projection target | Current evidence rule |
|---|---|---|---|
| Claude | `hosts/claude.yml` | `.claude/presentation-skills.md` | Projection and executable smoke only; no verified support without evidence IDs. |
| Codex | `hosts/codex.yml` | `.codex/presentation-skills.md` | Projection and executable smoke only; no verified support without evidence IDs. |
| Copilot | `hosts/copilot.yml` | `.github/copilot/presentation-skills.md` | Missing or unavailable CLI reports `not_run`. |
| OpenCode | `hosts/opencode.yml` | `.opencode/presentation-skills.md` | Missing executable reports `not_run`. |

`host conformance --all` reports each host separately. `executable_smoke.status`
can be `passed`, `failed`, or `not_run`. `not_run` is an exact reason, not a
support claim. `evidence_event_ids` must stay empty until real host evidence is
recorded.

Missing or unavailable executables produce warning-backed `not_run` results.
Resolved executables that fail their smoke command produce failed conformance and
exit non-zero, even when static projection files are present.
