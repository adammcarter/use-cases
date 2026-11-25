# `cargo-test` transformer

**Job:** results · **State:** built, proven in `UseCases/Acceptance/test_languages.py`

Reads the console output of `cargo test`. Stable Rust has no machine-readable test report.

## Setup

```yaml
validations:
  - id: cargo-test
    report: cargo-test.txt
    run: [sh, -c, 'cargo test --no-fail-fast > "$1" 2>&1', sh, "{report}"]
    transformer: cargo-test
```

`--no-fail-fast` matters. Without it, cargo stops at the first failing test binary, so later tests never run and their links honestly get "its test didn't run".

## How it matches tests to links

- It reads `test <path> ... ok | FAILED | ignored` lines.
- It finds `fn name(` first in the file named by the preceding `Running …` line, then anywhere under `src/` and `tests/`.
- Unit tests inside source files and integration tests under `tests/` both work.

| Line | Result |
|---|---|
| `ok` | `pass` |
| `FAILED` | `fail` |
| `ignored` | `incomplete` |
