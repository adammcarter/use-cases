# Authored schemas

Structural JSON Schemas (Draft 2020-12) for the files people write:

Every `pattern` that ends a value ends `$(?!\n)`, not `$`: some regex engines let `$` match before a final line break, and a name ending in one must be refused by every engine.

| Schema | File it checks | Chapters |
|---|---|---|
| `workspace.schema.json` | every `use-cases.yml` scope file | 04, 09 |
| `use-cases.schema.json` | use-case definition files under `use_cases_dir` | 02, 06, 08 |
| `use-case-groups.schema.json` | the root `use-case-groups.yml` | 03 |
| `bridge.schema.json` | the optional root `use-cases-bridge.yml` | 10, 14 |

```text
 use-cases.yml ─────────── workspace.schema.json      core
 use-cases/**/*.yml ────── use-cases.schema.json      core (links optional)
 use-case-groups.yml ───── use-case-groups.schema.json core
 use-cases-bridge.yml ──── bridge.schema.json         optional helpers
```

What the schemas enforce:
- closed field sets, with unknown fields INVALID
- ID grammar for use cases, scenarios, routes, bindings and validation ids
- route shape: type, covers, gating, and optional procedure, manual bindings and resources
- manual bindings are `kind: manual` only, with `start` and `end` both present or both absent
- project-relative paths only, never absolute and never escaping with `..`
- bridge report names are portable names, never paths; `working_dir` folders never inside `.use-cases/`; `{report}` as the only placeholder (a near miss of it, such as `{reprot}`, is refused by a core check, which names it; any other word in braces is plain text); `record` and Windows device names reserved

What stays a core check (chapter 09), because JSON Schema can't express it:
- DRAFT and READY state
- scenario references in `covers`
- duplicate resolved IDs
- whether files and `working_dir` folders exist, and whether line ranges fit
- glob matches
- marker pairing
- symlinks
- the READY warnings

Run the checks with `docs/schemas/engine/validate.py`. The latest output is in `docs/schemas/engine/VALIDATION.txt`.
