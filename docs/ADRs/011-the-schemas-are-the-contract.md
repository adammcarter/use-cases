# ADR 011: The published schemas are the contract, enforced on every exchange

## Status

Accepted - 2026-09-25

## Context

The core and the helpers meet at files: the transformer requests and responses, and the run folders the core writes (`run.json`, `start.json`, `results.jsonl`, `completion.json`, `run-order.json`). Chapters describe those files and schemas pin their shape, but a schema that no running code is held to drifts silently: an implementation can write run ids, field names and diagnostics that the schemas reject, and send transformers fields the contract does not define, with no test noticing.

For the core and the transformer layer to be foundations other implementations build on, the shapes have to be the ones an implementation actually exchanges.

## Decision

- The JSON Schemas under `docs/schemas/` are the normative shape of every file the core and helpers exchange. When a chapter's prose and a schema disagree, the schema wins and the prose is corrected.
- The acceptance suite checks, after every test, every file the core wrote to any results store and every request and response it exchanged with a transformer, against those schemas (`UseCases/Acceptance/conftest.py`). A test that deliberately feeds a broken transformer is marked, and only its requests are checked.
- `validate.py` checks every schema against positive and negative samples, every published chapter example, and every fixture YAML file.
- Transformers receive only what the contract defines: lines, never the core's byte offsets.

## Consequences

- Good: an implementation in any language can be tested against the same schemas and chapter examples and be known to interoperate with every transformer.
- Good: drift is caught the moment it happens.
- Cost: every contract change touches a schema, a chapter and usually `validate.py` together.
- Cost: schemas pin shape, not meaning. Rules such as "a result names a key the core sent" stay core checks with their own tests.

## Considered Options

- **Schemas as documentation only:** cheaper, but this is the option that had already drifted.
- **Check only in `validate.py`, with hand-written samples:** samples prove the schema, not the implementation.

## Confirmation

- `UseCases/Acceptance/conftest.py` checks, after every acceptance test, every stored file, every transformer request and response, and every `--json` document against these schemas.
- `docs/schemas/engine/VALIDATION.txt` records the latest validator run.

## Related Links

- `docs/schemas/engine/README.md`
- `docs/design/10-bridge-settings-and-transformers.md`
- `docs/design/12-results-storage.md`
