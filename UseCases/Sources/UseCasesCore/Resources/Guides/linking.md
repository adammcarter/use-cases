# Linking code

Tie a use case to the tests that prove it and the code that does it, so the tool knows which results belong to it and notices when that code changes.

## Two kinds of link

| Link | Around | What it does |
|---|---|---|
| validation link | a test that proves one of the use case's routes | the test's result becomes the route's verdict |
| implementation link | the code that does the behaviour | a change to that code means the verdict is out of date |

Links are optional. A use case with none is still READY, but then only `use-cases record` can prove it, and only changes to its own wording are noticed. `use-cases status <id>` warns about a use case with no links.

## Markers

A marker is a pair of comments in your code. Use whatever comment syntax the file has; the tool only looks for `@use-case:`.

Example, from a shell test script (`tests/total-test.sh`):

```text
# @use-case:basket.discounts#unit-tests.capped-at-zero
test="capped at zero"
[ "$(sh src/total.sh 3 5)" = "0" ] || failure='<failure message="a 5 discount on 3 should be 0"/>'
# @use-case:end basket.discounts#unit-tests.capped-at-zero
```

| Marker | Kind of link |
|---|---|
| `<use case id>#<route id>.<name>` | validation link for that route |
| `<use case id>#<name>` | implementation link |

`<name>` is yours to choose (lowercase words joined by `-`); naming it after the scenario helps a reader. The use case id is the full id, prefixes included.

```text
// @use-case:basket.discounts#never-negative
// @use-case:end basket.discounts#never-negative
<!-- @use-case:basket.discounts#receipt-total -->
<!-- @use-case:end basket.discounts#receipt-total -->
```

## Marker rules

- Put each marker on a line of its own. The linked code is the lines strictly between the two.
- Pairs close like brackets. Different markers may nest; an end with no start, a start never closed, or pairs that cross make the workspace INVALID.
- One marker may appear around several pieces of code; each is its own link.
- A marker naming a use case or route that does not exist is only a warning: code may run ahead of its use cases.
- Markers inside the use case files, `use-cases-bridge.yml`, `use-case-groups.yml` and `.use-cases/` are ignored.

## Manual bindings

When a file cannot hold comments, or you would rather not touch it, bind it from the use case instead. A binding on the use case is an implementation link; one inside a route is a validation link for that route:

```yaml
bindings:
  - id: legacy-totals
    kind: manual
    locator:
      file: src/legacy_totals.sh
      start: { line: 40 }
      end: { line: 78 }
```

Leave out `start` and `end` to bind the whole file. Line numbers do not move with the code: update them after a refactor. Prefer markers where you can.

## See the links

```text
$ use-cases links
basket.discounts  implementation         src/total.sh:5-6
basket.discounts  validation unit-tests  tests/total-test.sh:8-9
```

`use-cases links basket` shows only the use cases under an id prefix. Warnings about markers are listed under the links whatever you ask for.

## When code moves

Move the markers with the code. A pair left behind with nothing between it is a warning, shown by `validate`, `links` and `status`:

```text
$ use-cases validate
✓ valid · 1 use case (1 ready, 0 draft) · 2 links · 1 file
warning: src/total.sh:5: empty marker region: basket.discounts#never-negative
→ use-cases status
```

## How a test's result reaches its link

`use-cases verify` runs the commands in `use-cases-bridge.yml`. Each command writes a report, and a transformer reads that report and matches each test to the validation link around it. A test the transformer cannot match is listed in the run as unlinked; its route then reads "its test didn't run". When that happens, check that the test's declaration (its name, as the report gives it) is inside the marker pair. `use-cases docs verifying` covers the bridge settings.
