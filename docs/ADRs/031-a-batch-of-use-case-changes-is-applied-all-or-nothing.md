# ADR 031: A batch of use case changes is applied all or nothing, in one fixed order

## Status

Accepted - 2026-10-10

## Context

Fitting a request into existing use cases (chapter 21, step 4) often means several changes at once: one use case replaced, another extended, a third added. Made one command at a time, they can stop halfway, leaving files that match neither the old state nor what the person approved, and what is written can drift from what they were shown. The owner chose batching as a new command, keeping `save` and `remove` for single changes, and a fixed order: delete, then add, then update.

## Decision

- **`use-cases apply --file F|-`** and the tool **`use_cases_apply`**: a batch with `remove` (use case ids) and `save` (whole use cases).
- **One fixed order:** every removal, then every addition, then every update, whatever order the file lists them in. Whether a save adds or updates is decided by the core from its id.
- **Each use case at most once in a batch.**
- **Checked once, as a whole:** every change is made to the files as the changes before it left them; the finished result is loaded as the workspace would be, and anything INVALID means nothing is written.
- **The dry run is what is signed off:** `--dry-run` lists every change in the order it runs, and that batch is exactly what is applied.
- `save` and `remove` are the one-change cases of the same planning, so a batch follows exactly their rules: one use case's lines, the recommended structure, warnings for markers.

## Consequences

- Good: a signed-off proposal reaches the files whole, or not at all; nothing is ever left half changed.
- Good: one order means the same batch always lands the same way.
- Cost: one more command and tool. A batch is not split into what could succeed: one bad change refuses all of it, which is the point.

## Considered Options

- **No batching:** `save` and `remove` one at a time after one sign-off. Simpler, but can stop halfway, and the written result can drift from what was approved.
- **`save` taking a batch:** no new command, but `save` would then also remove, which blurs what its name says.
- **The order the file lists:** flexible, but the same changes could land differently depending on how they were written.

## Confirmation

- `test_edit.py`: delete, add, update whatever the file order; a replace in one batch; emptying a file then adding to its group; two new use cases sharing one new file; every kind of bad batch writing nothing; one invalid change and nothing written; the dry run writing nothing and matching the real run; people seeing the batch in the order it runs.
- `test_mcp.py`: a batch through the tool, its dry run equal to the real run.

## Related Links

- `docs/design/16-cli-surface.md` §14
- `docs/design/21-agent-workflows.md` (step 4 and 5)
- ADR 028 (show, save, remove)
