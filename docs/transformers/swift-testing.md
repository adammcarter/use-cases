# `swift-testing` transformer

**Job:** results · **State:** built, proven in `UseCases/Acceptance/test_swift_project.py`

Reads Swift Testing's event stream and gives one result per validation link.

## Setup

```yaml
validations:
  - id: auth-tests
    report: auth-tests.jsonl
    run: [swift, test, --experimental-event-stream-output, "{report}", --experimental-event-stream-version, "0"]
    transformer: swift-testing
```

Plain `swift test` writes no report. The event-stream flags are required, either in `run` or in your own test command when you run the tests yourself between `use-cases verify --start` and `--finish`.

`swift test` takes `--experimental-event-stream-output` only once. A test wrapper that already passes it (to read the stream itself) must be pointed at the `{report}` path, the path `--start` gave, instead of adding a second flag.

## How it matches tests to links

- Every test in the stream carries its source file and declaration line.
- A test's result goes to the validation link whose range contains that line.
- A test inside no link is reported as unlinked.

| Stream says | Result |
|---|---|
| test ended with no issue | `pass` |
| an issue recorded (`isKnown: false`) | `fail` |
| a known issue (`isKnown: true`), and nothing worse | `incomplete`: an expected failure is not a pass (chapter 10 §13) |
| test skipped | `incomplete` |

## What it relies on

- The event-stream flag is marked experimental by Swift. The format may change, and this transformer absorbs that.

## What it cannot see

- **XCTest (verified absent):** XCTest tests don't appear in this stream, or in Swift's `--xunit-output` either. Their links receive no result, and the core reports "its test didn't run". That is never a false pass. Use [`swift-test`](swift-test.md) to cover XCTest too.
