# Quirks

The gotchas that catch people new to Use Cases, each with what to do instead.

## validate never runs a test

`use-cases validate` only checks that the files are right, and is safe to run on every save. `use-cases verify` is what runs tests and keeps verdicts. A valid workspace says nothing about whether the code works.

## Unverified means no verdict here, never failed

Verdicts belong to one checkout, like test results, and are never committed or copied. A fresh clone shows every use case unverified until something runs there:

```text
no verdicts in this checkout yet: 1 use case (1 draft), none run here
```

Nothing is wrong. Run the tests if you want a baseline; CI may already prove them for everyone.

## A failing test does not fail the command

When a test fails, `use-cases verify --run` still exits 0, because it did its job and kept the verdict. Exit 1 means a run error (the tests could not run, or wrote no report). Ask `use-cases status --gate` whether anything blocks; it exits 1 when something does.

## YAML values that need quotes

Some plain values mean different things to different YAML readers, so they are refused until quoted: `yes`, `no`, `on`, `off`, times like `1:30`, dates like `2024-01-01`, numbers like `1e3`.

```text
$ use-cases validate
error: use-cases/basket.yml:31: 'No' reads as the boolean false in YAML 1.1 and as text in YAML 1.2; quote it
```

Write `title: "No"`. Quote text that contains ` #` too, or YAML reads the rest as a comment:

```text
error: use-cases/basket.yml:39: 'Check voucher' is followed by '#4 is taken off'; quote the whole text, or put the comment on its own line
```

## A comma splits a one-line list

In `when: [A, then B.]`, YAML sees two items. Use one `- ` item per line, or quote any sentence with a comma in it.

## A minus word needs quotes, or -- first

`use-cases search total -receipt` is refused, because `-receipt` looks like an option. Quote the whole query (`use-cases search "total -receipt"`), or put `--` before it. The same holds for `use-cases docs`.

## --next is passed alone

The token of `--next` carries the whole search. Adding words or flags beside it is refused:

```text
error: --next continues a search: pass the token alone, with no words, --like or filters
```

## remove keeps the evidence

`use-cases remove` takes a use case out of its file, but its verdicts stay in `.use-cases/`, and markers that still name it stay in the code (each is listed as a warning). Take the markers out yourself.

## Short run ids look alike

Run ids are ordered by time, so runs started close together share their first digits, and human output shows only the first 8. When you abort or finish a particular run, copy the full 32-digit id from `use-cases verify --start`, or read it from `--json`.

## Changing a use case's words puts its verdict out of date

Changing its intent, a scenario a route covers, or the route itself makes that route `stale`, as changing its code does. Its title, description, value tier and out of scope can change freely. Changing the promise (title, description, value tier, intent, scenarios or out of scope) also makes an approved use case read `changed since approved`.

## Marker text kept as data

A file that holds marker text as data, such as test data, a fixture, or a copy in build output, is read for markers like code is. A start with no end there makes the workspace INVALID:

```text
error: tests/fixtures/sample.swift:3: marker 'shop.cart.add#add-item' is never closed: no '@use-case:end shop.cart.add#add-item' follows it; if this file holds marker text as data, exclude it with discovery.exclude in use-cases.yml
```

Exclude the folder in the root `use-cases.yml`, and it is never searched for markers or use cases:

```yaml
discovery:
  exclude:
    - "tests/fixtures/**"
```

## Markers stay behind when code moves

Moving marked code to a new file leaves the marker pair empty. That is a warning, not an error, so it is easy to miss: move the markers with the code.

## A DRAFT cannot be recorded

`use-cases record` refuses a DRAFT ("it cannot be verified yet") and names what it is missing. Give it a value tier and whatever else it lacks first.

## Never write approved by hand

The `approved` field holds a fingerprint of the promise. Only `use-cases approve` and `use-cases apply --approved-by` write it; `save` keeps the one a use case has and refuses one that differs.
