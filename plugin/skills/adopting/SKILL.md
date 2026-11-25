---
name: adopting
description: Use to bring a repo that has code but no use cases in, one small area at a time, describing what the code does today.
---

# Adopting

Brings an existing repository in, one small, well-tested area at a time. It describes what the code does today, not what it should do: changing behaviour is a normal request afterwards, through the use-case-driven-development skill.

1. Pick one small area with tests.
2. Describe what it does today as use cases: every fit is new (`use-cases render proposal`).
3. The person signs off (`use-cases apply --approved-by NAME`).
4. Mark the existing tests and code; `use-cases verify --run` shows verified.
5. The next area, when the person chooses. Partial adoption is valid.

`use-cases approve --all` is only for a repo that already has use cases and is turning the gate on.

## Before you start

The repository needs a workspace: `use-cases validate` succeeds. If it has none, run the setup skill first. It also needs a test command in `use-cases-bridge.yml` for the area's tests; if there is none, propose one and add it only on the person's yes.

## 1. Pick one small area

Suggest two or three candidates: small, with good tests, and behaviour the person cares about. Let the person choose. One area at a time, so the person is never asked to sign off a whole codebase at once.

## 2. Describe it as it is today

Read the area's tests first, then its code. Write one use case per behaviour the tests prove: a title, the intent, the scenarios the tests already cover, a validation route for those tests, and a value tier you propose. Write what the code does, even where it looks wrong; note anything that looks wrong for the person, and do not fix it.

Search first, so nothing is described twice: `use_cases_search` with `like` set to each draft (`use-cases search --like -`). On a repository with no use cases this finds nothing, which is expected.

Put them in one proposal, every fit new: `save` holds the use cases, `title` names the area, and `you_see` says in plain words what each one covers. Check it: `use_cases_render` with `kind` `brief`, and `use_cases_apply` with `dry_run` true, both succeed.

## 3. The person signs off

Show the proposal (`use_cases_render` with `kind` `proposal`) as it is. Make clear these describe today's behaviour. On their approval, record it with their name: `use_cases_apply` with the same `save` and `approved_by`.

**Check:** `use_cases_show` reads `approval` `approved` for each.

## 4. Mark the existing tests and code

Put validation markers around the tests that prove each route, and implementation markers around the code that does each behaviour (`use-cases docs linking`). Change no test and no code beyond adding markers.

**Check:** `use_cases_links` lists the tests and the code, and `use_cases_verify_tests` with `step` `run` leaves each use case **verified**.

A route that fails on today's code means the description is wrong, or the test does not prove what you thought: fix the use case or the markers, never the code. A route that reads "its test didn't run" has its marker in the wrong place; `use-cases docs linking` explains how results reach a marker.

## 5. The next area

Report what is now covered and verified, then stop. Start another area only when the person chooses. A repository that is only partly adopted is valid: code with no use case is simply not covered yet.

## The sign-off gate

`use-cases approve --all --by NAME` approves every use case as it reads now. It is for a repository that already has use cases and is turning on `sign_off: required`: it catches up in one commit, after the person has reviewed them. Never use it to skip the sign-off of newly described areas.

## Never

- Never change behaviour while adopting: no code or test changes beyond markers.
- Never describe what the code should do instead of what it does.
- Never adopt more than the area the person chose.
