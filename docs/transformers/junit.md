# `junit` transformer

**Job:** results · **State:** built, proven on five tools in `UseCases/Acceptance/test_languages.py`

Reads JUnit-style XML, the most widely written test report format. The report can be one file or a folder of files.

## Why one transformer serves many tools

Tools that write JUnit XML disagree on one thing: where a test lives. Settings tell the transformer how to find each test in the source.

| `find` | The report gives | Used for | Settings |
|---|---|---|---|
| `file-line` | file and line | pytest (`-o junit_family=xunit1`) | `line_base: 0` if lines count from 0; `base` if paths start somewhere other than the working folder |
| `file-name` | the file, no line | `node --test --test-reporter=junit` | `base` if paths start somewhere other than the working folder |
| `pattern` | a name only | CTest, Maven Surefire, Gradle | `files` (glob), `patterns` (declarations with `{name}` / `{method}`), `class_file` |

## Setups proven

```yaml
# Python
run: [python3, -m, pytest, -q, -o, junit_family=xunit1, "--junitxml={report}"]
settings: { find: file-line, line_base: 0 }

# JavaScript
run: [node, --test, --test-reporter=junit, "--test-reporter-destination={report}"]
settings: { find: file-name }

# C
run: [sh, -c, 'cmake -S . -B build && cmake --build build && ctest --test-dir build --output-junit "$1"', sh, "{report}"]
settings: { find: pattern, files: "tests/**/*.c", patterns: ["static int {name}(void)"] }

# Java (no report name: {report} is a folder; pom.xml sets <reportsDirectory>${junitDir}</reportsDirectory>)
run: [mvn, -q, -B, test, "-DjunitDir={report}"]
settings: { find: pattern, files: "src/test/**/*.java", class_file: true, patterns: ["void {method}("] }

# Kotlin (no report name: {report} is a folder; build.gradle.kts sets reports.junitXml.outputLocation from junitDir)
run: [gradle, test, -q, "-PjunitDir={report}"]
settings: { find: pattern, files: "src/test/**/*.kt", class_file: true, patterns: ["fun {method}(", "fun `{method}`("] }
```

## In a monorepo

Give the validation a `working_dir`. The command runs there, and relative paths in the report are read from there by default:

```yaml
  - id: pricing-tests
    working_dir: pricing
    report: pricing.xml
    run: [python3, -m, pytest, -q, -o, junit_family=xunit1, "--junitxml={report}"]
    transformer: junit
    settings: { find: file-line, line_base: 0 }
```

`base` overrides that folder when a tool reports paths from somewhere else. `pattern` globs are always written from the workspace root, for example `services/api/src/test/**/*.java`.

## Outcomes

| XML | Result |
|---|---|
| `<failure>` | `fail` |
| `<error>` | `error` |
| `<skipped>`, or CTest `status="notrun"` / `"disabled"` | `incomplete` |
| otherwise | `pass` |

Several test cases at one location with different names (parametrised tests) combine into the worst. The same test case written again (a retry plugin such as Gradle's test-retry or pytest-rerunfailures) counts by its final attempt, and Surefire's `<flakyFailure>` inside a passing test case is a pass: each retry of a test counts by its final attempt (chapter 10 §13). pytest's xfail arrives as `<skipped>`, so an expected failure is `incomplete`.

## What it cannot see

- A test whose declaration can't be found, or is found more than once, is reported unlinked with a diagnostic. It is never guessed.
- JUnit XML has no standard location field, so every tool needs the right `find` settings.
- JUnit XML has no "pending" outcome. Cucumber, for one, writes a pending scenario as an empty `<failure/>`; read Cucumber with [`cucumber-messages`](cucumber-messages.md) instead.
