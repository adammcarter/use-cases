# `cucumber-messages` transformer

**Job:** results · **State:** built, proven in `UseCases/Acceptance/test_languages.py` (fixture `fixtures/bdd`)

Reads Cucumber's message stream: NDJSON, written by `--format message:<file>`. It is the report format every Cucumber implementation shares, so one transformer covers cucumber-js, Cucumber-JVM and the others that emit messages.

## Setup

```yaml
validations:
  - id: cucumber
    report: cucumber.ndjson
    run: [npx, cucumber-js, --no-strict, --format, "message:{report}"]
    transformer: cucumber-messages
```

On Windows, cucumber-js reads `--format message:D:\...` as `name:path` and splits at the drive letter's colon, so the absolute `{report}` path fails there. Run it through a small wrapper script that passes the report path relative to the project, which has no drive letter.

`--no-strict` matters. By default Cucumber exits 1 when a scenario is only pending. The core treats a non-zero exit with no failing result as a build failure (chapter 13), so a strict run would lose every verdict. Pending scenarios are still reported, as `incomplete`.

## Markers in feature files

Markers are comments in the `.feature` file, around a scenario or a scenario outline:

```gherkin
  # @use-case:library.returns.fines#acceptance.late-days
  Scenario Outline: Late returns are fined per day
    When "ana" returns "9780141439587" on <returned>
    Then the fine is <fine> pence

    Examples:
      | returned   | fine |
      | 2026-03-16 | 20   |
      | 2026-03-22 | 140  |
  # @use-case:end library.returns.fines#acceptance.late-days
```

## How it matches tests to links

- Each scenario, and each example row of an outline, is one test, located at its own line in the feature file. No name searching is needed.
- Example rows sit inside the outline's marker region, so they merge into that link, worst first.
- Feature paths start at the validation's `working_dir`; `settings.base` overrides that.
- When a scenario is retried, only its last attempt counts.

| Step results in the scenario | Result |
|---|---|
| all `PASSED` | `pass` |
| any `FAILED` | `fail` |
| any `AMBIGUOUS` | `error` |
| any `PENDING`, `UNDEFINED`, `SKIPPED` or `UNKNOWN`, none worse | `incomplete` |

## Why not JUnit

Cucumber's JUnit output writes a pending scenario as an empty `<failure/>`, so the `junit` transformer would call it a fail. The message stream keeps pending apart, and carries exact lines.
