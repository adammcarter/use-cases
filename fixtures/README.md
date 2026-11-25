# Fixture repos

Small, realistic repositories used to prove that Use Cases works across languages and test tools. Each was written as a normal project first, with no thought for use cases, then adopted in steps.

```text
 <language>/1-plain       a realistic small repo: code, tests, build config. No use cases.
          /2-use-cases    a copy of 1, plus use cases and links (ring 1 + ring 2). No helpers.
          /3-bridge       a copy of 2, plus use-cases-bridge.yml and a results transformer (ring 3).
```

| Language | Repo | Test tool | Notable test habits |
|---|---|---|---|
| Python | invoicing | pytest | parametrised tests, a skipped test |
| C | ringbuf | CMake + CTest | one test binary, one CTest entry per case |
| Rust | exprlex | cargo test | unit tests inside source files, an integration test, an ignored test |
| Java | ledger | Maven + JUnit 5 | `@Nested`, `@ParameterizedTest`, `@Disabled` |
| Kotlin | todo | Gradle + kotlin.test | backtick test names, `@Ignore` |
| Go | linkshort | go test | table-driven subtests, `t.Skip` |
| JavaScript | human-duration | node --test | `describe` / `it`, `it.skip` |
| Swift | RateLimit | swift test | Swift Testing with arguments, plus an XCTest class |
| BDD (JavaScript) | library-loans (`bdd/`) | Cucumber | Gherkin features, a Background, a Scenario Outline, a pending step |
| Mixed | shop (`monorepo/`) | pytest + go test + node --test | shared `catalog/prices.json`, three services, a Makefile |

Every `1-plain` repo builds and passes with its own tool.

Every `2-use-cases` repo:
- still builds and passes with its own tool (markers are comments)
- loads in the core with every marker and manual binding resolved and no diagnostics
- works with the core alone: status, and `use-cases record` for manual checks

Every `3-bridge` repo adds one `use-cases-bridge.yml`: the project's usual test command, asked for a report, and a transformer. `use-cases verify --run` then gives every use case its verdict from one test run.

## What the fixtures proved

`UseCases/Acceptance/test_languages.py` runs the same six scenarios in all nine repos (54 checks):

| Scenario | Proven in every repo |
|---|---|
| One run | every use case gets the right verdict, including `incomplete` for skipped tests, and tests with no use case are listed |
| Linked code edited | only the use cases linked to that code go stale |
| A test fails | its use case is `failed` |
| The build breaks | a run error; no use case is marked failed |
| A filtered run skips linked tests | those use cases never verify ("its test didn't run"); this check fails in every repo when the rule is removed |
| Tests you ran yourself | `verify --start`, the repo's own test command writing its report to the path `--start` printed, then `verify --finish` gives the same verdicts; an edit before `--finish` means "code changed during the run" |
| Fields from a future version | a newer core's request fields and a newer transformer's response fields change no verdict |

Findings:
- **The contract held, with one change: a report can be a folder.** Maven and Gradle write one JUnit file per test class, and a Swift run needs its event stream plus the console.
- **Each run owns its reports, so tools must write where they are told.** Most tools take a report path on the command line. Maven Surefire and Gradle don't, so the Java and Kotlin repos each gained one build property that points the JUnit folder at `{report}` (`-DjunitDir=...`, `-PjunitDir=...`). Without the property the build behaves exactly as before.
- **Most tools report a test's name, not its line.** Transformers find the declaration in the source (C, Java, Kotlin, Go, Rust, JavaScript). No core change was needed.
- **One configurable `junit` transformer served five tools** across Python, JavaScript, C, Java and Kotlin.
- **No tool's clock is needed.** Maven Surefire and `cargo test` record no start time, and Swift Testing records one only after building. The start point (`verify --start`) makes report times irrelevant, so every tool works the same way whether the core or you run the tests.
- **XCTest is absent from Swift Testing's report (verified).** `swift-test` reads the console too.
- **`cargo test` needs `--no-fail-fast`,** or later test binaries never run. Without it their links honestly report "didn't run".
- **Cucumber needs its own transformer, not JUnit.** Its JUnit output writes a pending scenario as an empty `<failure/>`. Its message stream keeps pending apart and gives every scenario and example row an exact line, so `cucumber-messages` needs no name search.
- **Strict modes clash with the build-failure rule.** Cucumber exits 1 when a scenario is only pending. The core reads a non-zero exit with no failing test as a build failure, so the run command turns strict mode off (`--no-strict`). The core rule stayed: it is what refuses a half-written report.
- **YAML inline lists split sentences at commas.** Six scenario sentences were silently split. The schema caught the one that produced a number. Chapter 02 now warns about it.

## The mixed-language monorepo

`monorepo/` is a coffee-shop repo: a shared price catalog, a Python pricing service, a Go checkout service and a JavaScript storefront.
- Each service is its own scope with its own `use-cases.yml`, and the scopes compose under the root prefix `shop`.
- One use case, `shop.rules.bulk-discount`, is proved by tests in two languages: the Python quote and the Go checkout total must agree.
- One root `use-cases-bridge.yml` runs all three test tools.

`UseCases/Acceptance/test_monorepo.py` (10 checks) proves:

| Scenario | Result |
|---|---|
| One run of all three services | every use case verified; the cross-language use case merges its Python and Go results |
| Only the Python service runs (`--only`) | the cross-language use case is not verified: its Go half "didn't run" |
| A Go test fails | the cross-language use case fails, although Python passed |
| The Go build breaks | a run error for that service only; the Python and JavaScript verdicts stand |
| The shared catalog changes | both languages' routes of the use case that declares it go stale |
| A bridge file inside a service | refused: bridge settings are root-only |

Findings:
- **Each service runs in its own folder.** The first version needed `sh -c 'cd <service> && …'` in every command. That friction became the optional per-validation `working_dir` (chapter 10): the command runs there, and `junit` and `go-test-json` read relative paths from there, so no transformer setting is needed either.
- **Only declared inputs count, as designed.** The pricing and checkout tests also read the shared catalog. Their use cases don't declare it as a resource, so editing it doesn't make them stale (chapter 11). The one use case that declares it goes stale in both languages.

Adoption choices made in step 2, as a team might:
- mostly markers, in each language's comment style
- manual whole-file bindings where marking code felt heavy (Python tax table and discount rules, the C public header, the Java transfer service)
- one plain-language manual check (Python's rate-table review, non-gating)
- some tests deliberately left with no use case (for example Python's quantity validation, C's `starts_empty`, Java's `newAccountHasZeroBalance`)
- some skipped or ignored tests linked (Python reverse charge, Rust unicode operators, Kotlin recurring tasks, JavaScript weeks) and some left unlinked (Java interest, Go custom aliases, Swift burst credits)
