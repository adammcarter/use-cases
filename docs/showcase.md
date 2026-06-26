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
script already exists. A generated plan is prepared material until
`showcase start --plan-file` records a run against its content hash.

Use `capsule run --capsule <id>` when the persisted capsule should be performed
now. Instruction steps become action events. Static observation steps are
recorded as prompts for a real runtime observation; they do not become proof and
do not create pass verdicts by themselves. Command-backed observations can
record pass/fail verdicts in the same append-only showcase ledger. Successful
command-backed runs are finished automatically; runs with pending runtime
observations or failed commands stay open so the agent or user can continue,
pause to fix, waive with a reason, or abort.

Command steps are inert by default. They run only when the caller passes
`--execute-commands` and the capsule sets `permissions.command_execution: true`.
The runner executes an exact executable/argv pair without a shell, requires the
working directory to stay inside the repository, uses a small environment
allowlist, and records bounded/redacted stdout/stderr plus the exit code as the
observation.

User-required approval cannot be recorded by an agent or MCP tool. The trusted
path is the interactive CLI-mediated user approval command. Approval is only
valid after finish, and is bound to the plan hash and finish event.
