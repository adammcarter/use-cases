# Host Support

Use Cases Plugin treats Claude, Codex, Copilot, and OpenCode as first-class
host families, but profile existence is not proof of support.

| Host | Profile | Projection target | Current evidence rule |
|---|---|---|---|
| Claude | `hosts/claude.yml` | `.claude/use-case-matrix.md` | Projection and executable smoke only; no verified support without evidence IDs. |
| Codex | `hosts/codex.yml` | `.codex/use-case-matrix.md` | Projection and executable smoke only; no verified support without evidence IDs. |
| Copilot | `hosts/copilot.yml` | `.github/copilot/use-case-matrix.md` | Missing or unavailable CLI reports `not_run`. |
| OpenCode | `hosts/opencode.yml` | `.opencode/use-case-matrix.md` | Missing executable reports `not_run`. |

`host conformance --all` reports each host separately. `executable_smoke.status`
can be `passed`, `failed`, or `not_run`. `not_run` is an exact reason, not a
support claim. `evidence_event_ids` must stay empty until real host evidence is
recorded.

Each host row includes a `support` table:

```text
profile_available      profile was loaded as expectation data
projected              this host's managed projection file matches expected content
static_conformant      projection and canonical skill hashes match
executable_smoke       passed | failed | not_run
verified_with_evidence true only when evidence_event_ids is non-empty
```

Missing or unavailable executables produce warning-backed `not_run` results.
Resolved executables that fail their smoke command produce failed conformance and
exit non-zero, even when static projection files are present.
