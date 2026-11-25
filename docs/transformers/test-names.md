# `test-names` transformer

**Job:** links · **State:** built, proven in `UseCases/Acceptance/test_helpers.py`

Links tests to use cases by naming convention instead of markers, for teams that already name tests after what they check:

```js
test("demo.math.add#unit-tests.adds-numbers", () => {
  assert.equal(add(2, 3), 5);
});
```

## Setup

```yaml
links:
  - transformer: test-names
    settings:
      files: "test/**/*.js"
      pattern: 'test\("(?P<id>[^"]+)"'
      block: braces
```

| Setting | Meaning |
|---|---|
| `files` | glob of files to search, from the workspace root |
| `pattern` | a regular expression with a named group `id` capturing a marker-style id, `<use-case-id>#[<route-id>.]<binding-id>` |
| `block` | `line` (default): the matching line only. `braces`: from the match to the brace that closes the first `{` at or after it. Any other value is a settings error |

## How it links

- Each match becomes one link: a validation link when the id names a route, an implementation link otherwise.
- The link names lines; the core turns them into exact bytes, so freshness works exactly as for markers.
- An id for an unknown use case or route is a diagnostic, not a link.
- The core checks every link it returns (chapter 10): a link outside the project or past the end of its file stops the workspace loading rather than being guessed.

## What it relies on

- The naming convention is the team's; the transformer only reads it.
- `braces` counts characters and does not understand strings or comments. A `{` inside a test name would end the block early; use `line` for such code.

## Combining with markers

A binding can have one source only. A test named by convention and also wrapped in a marker for the same binding id is INVALID (chapter 08).
