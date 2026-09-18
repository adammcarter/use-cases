# Test Fixtures

Data, not tests. Every `.ts` file under `tests/` went with the TypeScript at
ADR 0007 row 10d; this directory stayed, at this path, for two reasons.

- **`workspaces/`** are the conformance corpus `schema validate-fixtures` walks.
  The path is baked into the product: `SchemaCommands.defaultFixture` is
  `tests/fixtures/workspaces/minimal-valid`, which decision 8 freezes, and it is
  recorded in the CLI dispatch corpus. `minimal-valid` is also the workspace
  that exercises all twenty-seven published schemas in order, which is what
  `FixtureWorkspaceValidatorTests` reads them for.
- **`backcompat/`** are captures of the published 0.4.0, 0.4.3 and 0.5.5
  binaries — `proven-0.5.5` is a real workspace a shipped release proved, key
  and all. They are the upgrade contract: regenerated only when a new baseline
  is cut, never edited. No Swift test reads them yet; that gap is recorded in
  `docs/rewrite/ladder-notes.md` under row 9.

The `.js` files in `backcompat/` are the fake product those captures verified.
They are fixture content, not a toolchain.
