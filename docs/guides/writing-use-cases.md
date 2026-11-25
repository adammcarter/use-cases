# Writing use cases

What goes in a use case, when it is READY or a DRAFT, where its file lives, and how to look at, add, change or remove one.

## A use case file

Use cases live in YAML files under `use-cases/`. One file holds one group of use cases, and its `prefix` starts every id in it:

```yaml
prefix: basket
use_cases:
  - id: discounts
    title: Discounts never make a total negative
    value_tier: critical
    intent: A discount larger than the basket brings the total to zero, never below.
    scenarios:
      - id: capped-at-zero
        when: [A discount of 5 is applied to a basket of 3.]
        then: [The total is 0.]
      - id: shown-on-receipt
        when: [A discount brings the total to zero.]
        then: [The receipt shows a total of 0.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [capped-at-zero]
      - id: try-it
        type: { kind: acceptance }
        covers: [shown-on-receipt]
        procedure:
          steps:
            - Add an item costing 3 to the basket.
            - Apply a discount of 5.
            - Read the total on the receipt.
```

Its full id is `basket.discounts`: the prefix, then the id. With a root prefix in `use-cases.yml` (`prefix: shop`), it would be `shop.basket.discounts`.

## The fields

| Field | Needed for READY | What it holds |
|---|---|---|
| `id` | yes | lowercase words joined by `-`; unique once the prefixes are added |
| `title` | yes | what the behaviour is called, in plain words |
| `description` | no | more detail, if it helps |
| `value_tier` | yes | how much it matters: `critical`, `core` or `supporting` |
| `intent` | yes | why the behaviour exists |
| `out_of_scope` | no | what it explicitly does not do |
| `scenarios` | at least one | each with an `id`, optional `given`, and at least one `when` and one `then` |
| `validation` | at least one route | how each scenario is proven (below) |
| `bindings` | no | links to code written in YAML instead of markers (`use-cases docs linking`) |
| `approved` | no | a person's sign-off, written only by `use-cases approve` or `use-cases apply --approved-by` |

Every scenario must be covered by at least one route that gates (the default).

## READY or DRAFT

A use case with every field the table marks "yes" is READY: it gets a verification status and can block a gate. One that is missing any of them is a DRAFT: it is listed, with what it is missing, and never blocks anything.

```text
· draft       example.getting-started  missing: value_tier
```

The smallest useful DRAFT is an `id` and a `title`. A file that cannot be read safely (bad YAML, a duplicate id, a route covering a scenario that does not exist) is INVALID, and every command refuses to judge anything until it is fixed.

## Value tiers

| Tier | Means | Who signs off a change |
|---|---|---|
| `critical` | must never break | the person, always |
| `core` | the product's main behaviour | the person, by default |
| `supporting` | helpful, lower risk | an agent, where the person has said it may |

With `sign_off: required` in the root `use-cases.yml`, the gate also holds use cases whose promise is not approved (`use-cases docs reading-status`).

## Validation routes

A route is one way of proving scenarios.

- `type` says what kind of proof it is: `unit`, `integration`, `contract`, `snapshot`, `ui`, `e2e`, `acceptance`, `performance`, or `{ kind: custom, name: ... }`.
- `covers` lists the scenarios it proves.
- `procedure` holds plain steps a person (or an agent) performs: a "try it" check. Its verdict is recorded with `use-cases record`.
- `gates_verification: false` makes a route count for nothing in the overall status, so it never blocks.

A route proven by tests needs marked tests (`use-cases docs linking`) and a command in `use-cases-bridge.yml` (`use-cases docs verifying`). The use case itself never names a command or a test tool.

## Where files go

The id decides the file. `basket.discounts` lives in `use-cases/basket.yml`; `payments.card.refund` would live in `use-cases/payments/card.yml` with `prefix: payments.card`. A use case needs a group: an id with only one part is refused. `save` and `apply` always put a use case where this layout says, so you never choose a file yourself.

## Look at one

```text
$ use-cases show basket.vouchers
# use-cases/basket.yml · READY
id: basket.vouchers
title: Apply a voucher code
value_tier: supporting
intent: A valid voucher code takes its amount off the basket.
out_of_scope: [Using two vouchers on one basket.]
scenarios:
  - id: valid-code
    when: [The shopper enters a valid voucher code.]
    then: [The voucher amount is taken off the total.]
validation:
  - id: unit-tests
    type: { kind: unit }
    covers: [valid-code]
```

`use-cases show <id> --json` gives the use case as `definition`, in exactly the shape `save` takes back: show it, change a field, save it.

## Add or change one

`save` takes one whole use case, as YAML or JSON, from a file or from standard input (`--file -`). It creates it, or replaces the use case with that id:

```text
$ use-cases save --file - --dry-run < discounts-change
would save: basket.discounts (replaced)
would update  use-cases/basket.yml

$ use-cases save --file - < discounts-change
saved: basket.discounts (replaced)
update  use-cases/basket.yml
→ use-cases status basket.discounts
```

- Only that use case's lines change. Every other use case, comment and blank line in the file stays as it was.
- A save that would leave the workspace INVALID is refused, and nothing is written.
- `--dry-run` shows exactly what the real run would do.
- Editing the YAML by hand is just as valid. `use-cases validate` checks your edit.

## Remove one

```text
$ use-cases remove basket.discounts --dry-run
would remove: basket.discounts
would update  use-cases/basket.yml
warning: src/total.sh:5-6 is still marked for basket.discounts
warning: tests/total-test.sh:8-9 is still marked for basket.discounts
```

Its verdicts stay in the results store; a remove never deletes evidence. Markers that still name it are listed so you can take them out.

## Several changes at once

`apply` takes a batch: ids to `remove`, and whole use cases to `save`. It runs every removal, then every addition, then every update, and writes all of it or none of it:

```yaml
remove:
  - example.getting-started
save:
  - id: basket.vouchers
    title: Apply a voucher code
    value_tier: supporting
    intent: A valid voucher code takes its amount off the basket.
    out_of_scope:
      - Using two vouchers on one basket.
    scenarios:
      - id: valid-code
        when: [The shopper enters a valid voucher code.]
        then: [The voucher amount is taken off the total.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [valid-code]
```

```text
$ use-cases apply --file - --dry-run < batch
would delete  example.getting-started
would add     basket.vouchers

would update  use-cases/basket.yml
would delete  use-cases/example.yml
warning: use-cases/example.yml:1: the comment # A worked example of a use case: fill it in, or delete this file. is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
warning: use-cases/example.yml:2: the comment # is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
warning: use-cases/example.yml:3: the comment # A use case is one behaviour your code promises, and the proof that it keeps the promise. is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
warning: use-cases/example.yml:4: the comment # This one is a DRAFT until it has a value tier, so it never blocks a gate. The prefix below is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
warning: use-cases/example.yml:5: the comment # starts every id in this file: example.getting-started. is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
warning: use-cases/example.yml:12: the comment # Choose a value tier to make this use case READY: critical, core or supporting. is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
warning: use-cases/example.yml:13: the comment # value_tier: core is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
warning: use-cases/example.yml:29: the comment # Each validation is a route to proof. A route with a procedure is checked by a person, is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
warning: use-cases/example.yml:30: the comment # who runs the steps and records the result with: use-cases record is dropped, as use-cases/example.yml goes with example.getting-started, its last use case
```

A comment that a change would drop is never dropped silently: each one gets a warning of its own, as above, in the dry run too. The dry run is what a person signs off; `apply` then writes exactly that batch.

## Record a sign-off

```text
$ use-cases approve basket.discounts --by Sam
approved  basket.discounts

update  use-cases/basket.yml
```

This writes `approved` on the use case: who, today's date, and a fingerprint of its promise (id, title, description, value tier, intent, scenarios, out of scope). Change any of those later and the use case reads `changed since approved` until it is approved again; changing how it is proven keeps the approval. `use-cases apply --approved-by Sam` approves every use case a signed-off batch saves. `use-cases approve --all --by Sam` approves every use case as it reads now, for a repository turning on the sign-off gate. Never write `approved` by hand.
