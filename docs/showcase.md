# Showcases

A showcase is a live run in front of the user or another reviewer. The agent can
drive the run, the user can drive it, or a script can drive it, depending on the
use case and user preference.

The mechanical flow is:

```text
start -> item -> observation -> verdict -> continue
                  |
                  +-> fail -> continue | pause_to_fix | waive_with_reason | abort
finish -> approval when required
```

Use `plan showcase` for a short, high-value demo and `plan walkthrough` for
broader coverage. Use `capsule plan` when a persisted smoke demo or golden path
script already exists.

User-required approval cannot be recorded by an agent or MCP tool. The trusted
path is the CLI-mediated user approval command.
