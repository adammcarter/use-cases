# Fixtures

Data, not tests. Every `.ts` file under the old `tests/` went with the
TypeScript at ADR 0007 row 10d; this directory stayed, and in 2026-09-18's
clean-up it was renamed `tests/` → `fixtures/`, because a directory called
`tests` holding no tests misleads every reader who opens it.

- **`workspaces/`** are the conformance corpus `schema validate-fixtures`
  walks. The path is baked into the product: `SchemaCommands.defaultFixture`
  is `fixtures/workspaces/minimal-valid`, and it is recorded in the CLI
  dispatch corpus, so the rename moved the constant and the four
  `schema_validate_fixtures_*` cases together. A default filesystem path is
  not one of the things ADR 0007 decision 8 freezes — that is the CLI JSON
  envelope, the 27 schemas, the marker syntax and the ledger formats.
  `minimal-valid` is also the workspace that exercises all twenty-seven
  published schemas in order, which is what `FixtureWorkspaceValidatorTests`
  reads them for.
- **`backcompat/`** are captures of the published 0.4.0, 0.4.3 and 0.5.5
  binaries — `proven-0.5.5` is a real workspace a shipped release proved, key
  and all. They are the upgrade contract: regenerated only when a new baseline
  is cut, never edited. No Swift test reads them yet; that gap is recorded in
  `docs/rewrite/ladder-notes.md` under row 9.

The `.js` files in `backcompat/` are the fake product those captures verified.
They are fixture content, not a toolchain.

Documents that RECORD the rewrite — `docs/rewrite/ladder-notes.md` and
`docs/rewrite/0.8.0-sign-off.md` — still say `tests/fixtures/` where they
describe what was true when they were written. That is deliberate: a record is
not edited to match a later tree.
