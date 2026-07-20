# Host Support

Use Cases treats Claude, Codex, Copilot, and OpenCode as first-class
host families, but profile existence is not proof of support.

| Host | Profile | Projection target | Current evidence rule |
|---|---|---|---|
| Claude | `hosts/claude.yml` | `.claude/use-cases.md` | Projection and executable smoke only; no verified support without evidence IDs. |
| Codex | `hosts/codex.yml` | `.codex/use-cases.md` | Projection and executable smoke only; no verified support without evidence IDs. |
| Copilot | `hosts/copilot.yml` | `.github/copilot/use-cases.md` | Missing or unavailable CLI reports `not_run`. |
| OpenCode | `hosts/opencode.yml` | `.opencode/use-cases.md` | Missing executable reports `not_run`. |

`host conformance --all` reports each host separately. `executable_smoke.status`
can be `passed`, `failed`, or `not_run`. `not_run` is an exact reason, not a
support claim. `evidence_event_ids` must stay empty until real host evidence is
recorded.

## Install boundary: what this package owns

Two separate things put Use Cases in front of an agent, and they must not be
confused with each other.

```text
  bootstrap text   hooks/session-start ──► injected at SessionStart   (this package)
  agent skills     .claude-plugin/*    ──► loaded as a Claude plugin  (this package)
  the MCP server   uc-mcp              ──► registered per host        (the installer that
                                                                       installs this package,
                                                                       e.g. agent-setup)
```

A SessionStart hook delivers text and nothing else. Claude loads **skills** only
from installed plugins, so the hook alone leaves `.agents/skills` unreachable —
which is why `.claude-plugin/plugin.json` declares the directory and
`.claude-plugin/marketplace.json` makes the package addable in the first place.

The global postinstall registers the plugin by calling the host's own
`claude plugin marketplace add` / `claude plugin install`. It never writes
`~/.claude/plugins/*.json` directly. That state belongs to Claude, and other
tools (for example agent-setup's `ensure-claude-plugins.sh`) converge it through
the same CLI; a second writer would silently disagree with the host about what
is installed.

Consequently this package registers its **own** marketplace, named `use-cases`.
It does not add itself to any other tool's marketplace, and no other tool needs
to list it. Registration failures are warnings, never install failures — the
skills simply stay unreachable, and `uc doctor skills` is what says so.

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
