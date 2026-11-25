# ADR 029: Search is one pipeline of words, filters, fields and pages, deterministic and offline

## Status

Accepted - 2026-09-29

## Context

Agents and people need to find use cases: to check what exists before adding one, to find what a change touches, and to spot use cases that already exclude something. The owner's notes ask for exact, fuzzy and "similar to this one" search. The owner expects search to grow complicated, and asked for a solid design first: paged results rather than a fixed top 10, filters on what is searched and on what comes back, and room for meaning-based search later without changing the core.

## Decision

- **One command, `use-cases search`, and one tool, `use_cases_search`.** It is a pipeline: which use cases (filters), which fields (`--in`), match and rank (the query), page. Every option belongs to one stage, so a new filter or field joins its stage and changes nothing else.
- **The query:** words, best first; `"exact phrases"`; `-word` and `-"phrase"` to leave out; typos and word starts forgiven unless `--exact`. Or `--like`, a whole use case in the shape `save` takes, to find the ones like it. Anything richer is a flag, never a query language.
- **Filters:** `--under`, `--group`, `--tier`, `--state`. AND across flags, OR inside one.
- **Fields:** `--in id,title,description,intent,scenarios,out_of_scope,validation`, all by default. An id or title match counts most. A match in `out_of_scope` is always reported, because it says the use case excludes exactly this.
- **Results:** each match carries its id, title, file, status, tier, a score and every place it matched; `--full` adds the whole use case.
- **Pages:** 20 by default, 1 to 100. A `--next` token carries the whole search and a digest of what it saw; it is passed alone, and a page from use cases that changed since is refused. Nothing is kept between calls.
- **Deterministic and offline, in the core:** matching is by words, with no model and no network. The same search on the same files always gives the same pages. The score orders one search's results and is not a contract, so a helper that ranks by meaning can be added beside the core later, giving the same document.

## Consequences

- Good: an agent can check "does this exist?" in one call, with `--like` and the use case it is about to save.
- Good: the answer is repeatable and explainable: every match says where and why.
- Good: the pipeline and the token leave room for more filters, fields and a meaning-based helper without changing the command's shape.
- Cost: words only. "Tap twice" does not find "double tap" until a meaning-based helper exists; an agent reading the top matches can judge meaning itself meanwhile.
- Cost: pages go in order; there is no jumping to page 3. And any change to the use cases or their statuses between pages means searching again.

## Considered Options

- **A fixed top 10:** simple, but hides matches and cannot grow.
- **Page numbers** (`--page 2` with the same flags again): lets people jump, but a caller can change a flag between pages and silently get wrong results, and detecting changed files needs a value passed back by hand.
- **Meaning-based search in the core** (embeddings or a model): finds "tap twice", but ties the core to a model and a network, against ADR 010.
- **A query language** (`tier:critical in:title`): compact for people, but a second syntax to parse and check, and harder for agents than typed arguments.

## Confirmation

- `test_search.py`: words ranked with a title above a scenario and every reason given; typos, swapped letters and word starts forgiven unless `--exact`; phrases required even beside other words; exclusions; `--like` never returning itself; `--in` limiting the fields; out-of-scope matches always labelled; every filter and the AND/OR rule; `--full` equal to `show`; pages covering every match once, in order, never empty; the token carrying the whole search, refused with other options, refused when use cases or verdicts changed, refused when not made by `search`; the same search giving the same answer.
- `test_mcp.py`: the tool's document equal to the command's, a query starting with `-`, paging and `like` through the tool.
- `test_scale.py`: 1,000 use cases searched in 0.4 s; 5,000 in 1.8 s.

## Related Links

- `docs/design/16-cli-surface.md` §15
- `docs/design/20-mcp-tools.md`
- `docs/schemas/output/cli-search.schema.json`
- ADR 010 (the core names no tool), ADR 027 (agents get the commands as tools), ADR 028 (show, save, remove)
