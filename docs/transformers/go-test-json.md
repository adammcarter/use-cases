# `go-test-json` transformer

**Job:** results · **State:** built, proven in `UseCases/Acceptance/test_languages.py`

Reads the event stream of `go test -json`.

## Setup

```yaml
validations:
  - id: go-test
    report: go-test.jsonl
    run: [sh, -c, 'go test -json ./... > "$1"', sh, "{report}"]
    transformer: go-test-json
```

For a Go module inside a monorepo, give the validation a `working_dir`. The folder holding `go.mod` defaults to it; `settings.module` overrides that:

```yaml
    working_dir: checkout
    run: [sh, -c, 'go test -json ./... > "$1"', sh, "{report}"]
    transformer: go-test-json
```

## How it matches tests to links

- Go reports a package and a test name, never a file or line.
- The package maps to a folder through the module path in `go.mod`, and each top-level test is found by `func TestX(` in that folder's `*_test.go` files.
- Subtests (`TestX/case`) roll up into their top-level test, and the worst outcome wins.

| Action | Result |
|---|---|
| `pass` | `pass` |
| `fail` | `fail` |
| `skip` | `incomplete` |

## What it cannot see

A marker can only wrap a whole top-level test function, so subtests share one result. That holds for table-driven tests, which are one function in Go.
