# Finding use cases

Find what already exists before you add or change a use case: by words, or by how alike two use cases are.

## Search by words

```text
$ use-cases search voucher
○ unverified  basket.vouchers  Apply a voucher code  title: "Apply a voucher code"  (also out of scope)

1 match
→ use-cases show basket.vouchers
```

Each line is one use case, best match first: its status, id, title, and where it matched. "also out of scope" means the use case explicitly excludes something your words name; read it before adding a use case that does that thing.

## What the words mean

| You type | Finds |
|---|---|
| `voucher` | use cases with this word; case is ignored |
| `vouchr` | small typos match too: one letter wrong, missing, extra or swapped, for words of 4 letters or more |
| `vouch` | the start of a word matches the whole word |
| `"two vouchers"` | this exact phrase |
| `"total -receipt"` | `total`, leaving out anything that mentions `receipt` |
| `total --exact` | only whole words exactly as typed |

Put the whole query in quotes when it has a minus word. When the query starts with a minus word, put `--` before the query, as in `-- "-receipt total"`, so it is not read as an option. A search with nothing to look for is refused. No match is not an error:

```text
$ use-cases search teleport
no matches
```

## Narrow it down

| Flag | Keeps |
|---|---|
| `--under basket` | use cases under an id prefix |
| `--group smoke` | the members of a group |
| `--tier critical,core` | those value tiers |
| `--state failed,draft` | those statuses, as `use-cases status` shows them |
| `--in intent,scenarios` | searches only these parts: `id`, `title`, `description`, `intent`, `scenarios`, `out_of_scope`, `validation` |

Every flag must hold; inside one flag, any of its values may.

```text
$ use-cases search total --tier critical
✓ verified    basket.discounts  Discounts never make a total negative  title: "Discounts never make a total negative"

1 match
→ use-cases show basket.discounts
```

## Before you add one: search with the whole use case

`--like` takes a whole use case instead of words, from a file or from standard input (`-`). Its title, intent, scenarios and out of scope are the query. A DRAFT is enough:

```text
$ use-cases search --like - <<'EOF'
id: basket.vouchers-twice
title: Use two vouchers on one basket
intent: A shopper can stack two voucher codes.
EOF
○ unverified  basket.vouchers   Apply a voucher code                   title: "Apply a voucher code"  (also out of scope)
✓ verified    basket.discounts  Discounts never make a total negative  intent: "A discount larger than the basket brings the total to zero, never below."

2 matches
→ use-cases show basket.vouchers
```

Here the closest use case already rules stacking two vouchers out of scope: adding the new one changes that decision, so it is a change to `basket.vouchers`, not just an addition. Read every close match with `use-cases show` before you decide.

## Read a match

- `use-cases show <id>` prints the whole use case.
- `--full` adds each match's whole use case to the results.
- `--json` gives `matches`, each with `use_case`, `title`, `file`, `status`, `value_tier`, `score` and `why` (every place it matched). `score` orders one search only; never compare it between searches.

## More than one page

Results come 20 to a page; `--page-size` takes 1 to 100. When more follow, the last line is the command for the next page:

```text
$ use-cases search total --page-size 1
✓ verified    basket.discounts  Discounts never make a total negative  title: "Discounts never make a total negative"

1 of 2 matches
→ use-cases search --next eyJleGFjdCI6ZmFsc2Us…
```

Pass `--next` with its token and nothing else: the token carries the whole search. If the use cases changed since the first page, the next page is refused; search again.

## For agents

The `use_cases_search` tool takes `query` (words) or `like` (a whole use case, as an object), the filters `under` and `group` (each one text) and `tier`, `state` and `in` (each a list), `exact`, `full`, `page_size`, or `next` alone. It returns the same document as `--json`.
