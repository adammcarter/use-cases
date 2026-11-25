# `swift-test` transformer

**Job:** results · **State:** built, proven in `UseCases/Acceptance/test_languages.py`

Covers both test frameworks a Swift package can mix: Swift Testing and XCTest.

## Setup

The report is a folder holding two files, so the validation has no report name and `{report}` is the run's folder for it:

```yaml
validations:
  - id: swift-test
    run: [sh, -c, 'swift test --experimental-event-stream-output "$1/events.jsonl" --experimental-event-stream-version 0 > "$1/console.txt" 2>&1', sh, "{report}"]
    transformer: swift-test
```

## How it matches tests to links

- **Swift Testing:** from `events.jsonl`. Every test carries its file and declaration line.
- **XCTest:** from `console.txt`, the only place its results appear (`Test Case '-[Module.Class testName]' passed`). Each test is found by `func testName(` in a test file declaring `class Class`.

Everything in [`swift-testing`](swift-testing.md) about outcomes and the experimental flag applies here too.
