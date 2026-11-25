---
name: use-case-driven-development
description: Use on every change in a repo whose AGENTS.md says it works use case first. The flow from a request to proven code, where every step ends on a command's output, never on your word.
---

# Use-case-driven development

The person decides behaviour by reading use cases; you do the work. Every step below ends on a check: a command whose output shows the step is done. Report that output. Never claim a step on your own word.

| Step | The check |
|---|---|
| 0 | AGENTS.md has the Use Cases block; otherwise offer setup |
| 2 Intent | `use-cases render intent` draws it; the person confirms it |
| 3 Discover | `use-cases search --like` each golden path; what it finds is in the brief, changed or untouched |
| 4 Brief | `use-cases render brief` and `use-cases apply --dry-run` both succeed |
| 5 Sign-off | `use-cases apply --approved-by NAME` succeeds; `use-cases show` reads approved |
| 6 Red | `use-cases links` shows the tests; `use-cases verify --run` shows the route failed, never error |
| Can it fail? | a planted defect turns `use-cases verify --run` failed; then it is reverted |
| Green | `use-cases links` shows the code; `use-cases verify --run` shows verified |
| Refactor | `use-cases verify --run` still shows verified; `use-cases status` shows no empty marked region (move markers with moved code) |
| 7 See it | the showcase skill |
| 8 Prove | the CI recipe: `use-cases verify --run`, then `use-cases status --gate` passes; `use-cases render results` is what the person sees |

## Tools

Use the MCP tools where the host has them; each runs the command and returns its `--json` document unchanged. In a shell, run the command with `--json`.

| Tool | Command | Arguments |
|---|---|---|
| `use_cases_search` | `use-cases search` | `query` (words) or `like` (a whole use case), `under`, `group`, `tier`, `state`, `in`, `exact`, `full`, `page_size`, or `next` alone |
| `use_cases_show` | `use-cases show` | `use_case` |
| `use_cases_links` | `use-cases links` | `target` |
| `use_cases_render` | `use-cases render` | `kind` (`intent`, `brief`, `proposal`, `results`), `input` |
| `use_cases_apply` | `use-cases apply` | `remove` (ids), `save` (whole use cases), `approved_by`, `dry_run` |
| `use_cases_save` | `use-cases save` | `use_case` (a whole use case), `dry_run` |
| `use_cases_remove` | `use-cases remove` | `use_case`, `dry_run` |
| `use_cases_approve` | `use-cases approve` | `use_cases` or `all`, `by`, `dry_run` |
| `use_cases_verify_tests` | `use-cases verify` | `step` (`run`, `start`, `finish`, `abort`), `only`, `run_id` |
| `use_cases_record_verdict` | `use-cases record` | `use_case`, `route`, `status`, `message`, `attach` |
| `use_cases_status` | `use-cases status` | `target`, `group`, `state`, `gate`, `strict` |
| `use_cases_validate_files` | `use-cases validate` | none |
| `use_cases_docs` | `use-cases docs` | `query` (a guide's name, or words) |

Every tool but `use_cases_docs` takes `workspace`. A refused call comes back as an error with the command's message: read it, fix the cause, try again. `use_cases_docs` answers how-to questions from the guides of the installed version, for example `{"query": "markers"}`.

## How to talk to the person

- **Plain words, ids last.** Show what the person will see and why; ids go at the end, if at all.
- **Show the core's layouts as they are.** `use_cases_render` returns `text`: put it in a code block, unchanged. Never draw a card or a proposal yourself.
- **Ask with choices.** Where the host has a choice prompt (approve, change, talk it through), use it; otherwise ask in plain words.
- **Ask only at fixed moments:** a thin intent, the sign-off, a showcase, and a conflict. Work in between.
- **Verdicts are like test results.** Never run a baseline unasked, and never report "no verdicts in this checkout" as a problem: unverified means nothing has run here, never failed.

## 0. Check the repository

Read `AGENTS.md`. The block starts with a line `<!-- use-cases:begin vN -->` and ends with `<!-- use-cases:end vN -->`, where `N` is the block's version: any version counts.

- Block there: follow this skill for the change.
- No block: offer the setup skill once. If the person declines, work as usual and do not use this flow.

## 1. The request

Anything from a few words to a full spec, or a spike's results. Note what it says about what, why and who.

## 2. Intent

If the request already says what, why and who, move straight on. Otherwise ask only for what is missing. Then draw it:

```json
{"kind": "intent", "input": {"what": "Let shoppers use a voucher code at checkout", "why": "Vouchers bring shoppers back", "who": ["shoppers at checkout", "marketing staff who hand out codes"]}}
```

```text
WHAT   Let shoppers use a voucher code at checkout
WHY    Vouchers bring shoppers back
WHO    shoppers at checkout · marketing staff who hand out codes
```

**Check:** the person confirms that text.

## 3. Discover

Use cases first, then the code as usual.

1. Write each golden path the person described as a draft use case: `id`, `title`, `intent`, and its scenarios if you have them. Keep their idea intact; do not reshape it to fit what exists yet.
2. Search with each one: `use_cases_search` with `like` set to that draft. Search by words too, for the nouns the request uses.
3. For each close match: `use_cases_show`, then `use_cases_links` for its tests and code. Read those, then the rest of the codebase as you normally would; not everything is covered by use cases.
4. Mention code that no use case covers. Do not fix it unasked.

**Check:** every use case the searches found appears in the brief, as changed or untouched. Nothing found is silently dropped.

Then pick the route:

| Route | When | What happens |
|---|---|---|
| fast path | a papercut or a tuning change ("4 s, not 40 s") | edit the use case and its test, confirm in one line (a critical one: record the yes, below), then step 6 |
| explore | what good looks like is unclear | a short, proven spike; its results come back as a better request (step 1) |
| new or changed behaviour | anything else that changes what the code promises | steps 4 and 5 |
| no behaviour change | a refactor, or a speed-up that promises nothing new | no sign-off; step 6 must end with everything still verified |

A bug fix decides at step 4 what is wrong: the use case (change it, with sign-off), or the code (the use case is right: add the missing scenario, a red test that reproduces the bug, then the fix).

A fast-path change to a critical use case is still the person's to confirm, in its one line. On their yes, record it: `use_cases_approve` with `use_cases` set to its id and `by` set to their name. Without that, a repository with `sign_off: required` blocks the gate on it as "changed since approved".

## 4. Brief

Write the proposal: the batch `use_cases_apply` takes, plus what only the conversation knows.

```yaml
title: Vouchers at checkout
remove: []                       # ids that go
save:                            # whole use cases, new or changed
  - id: basket.vouchers-expiry
    title: Refuse an expired voucher code
    value_tier: core
    intent: An expired voucher code takes nothing off and says why.
    scenarios:
      - id: expired-code
        when: [The shopper enters a voucher code that has expired.]
        then:
          - Nothing is taken off the total.
          - The shopper is told the code has expired.
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [expired-code]
untouched: [basket.vouchers]     # checked and left alone
fits: {}                         # id: extends or changes, for a save that changes an existing use case
you_see:                         # per use case: what the person will see
  basket.vouchers-expiry: '"This code has expired" under the code box'
decisions:                       # each conflict or open choice
  - question: What happens to an expired code?
    options: [refuse it, accept it within a day of expiry]
```

Every use case the change touches gets one of six fits:

| Fit | Means | In the batch |
|---|---|---|
| new | nothing like it exists | a save that adds |
| extends | an existing use case gains a scenario or an edge | a save that updates, with `fits` `extends` |
| changes | an existing use case behaves differently from now on | a save that updates, with `fits` `changes` |
| replaces | an old use case goes and this takes its place | a remove and a save |
| conflicts | both cannot be true | never yours to settle: it goes in `decisions`, and becomes one of the others once the person chooses |
| untouched | related, and stays exactly as it is | listed in `untouched` |

Write whole use cases, every field, as `use-cases docs writing-use-cases` describes. Use the same proposal for every call that follows.

**Check:** both succeed, so every change is valid before the person sees it:

- `use_cases_render` with `kind` `brief` and the proposal as `input`: the cards;
- `use_cases_apply` with the proposal's `remove` and `save`, and `dry_run` true.

A refusal names the problem: fix the proposal and run both again.

## 5. Sign-off

Show the person the cards and then the proposal (`use_cases_render` with `kind` `proposal`):

```text
PROPOSAL · Vouchers at checkout

  + NEW        Refuse an expired voucher code   you'll see: "This code has expired" under the code box
  = UNTOUCHED  Apply a voucher code             (checked, stays as it is)

  YOUR CALL    What happens to an expired code?:  1) refuse it   2) accept it within a day of expiry
  SIGN-OFF     yours: 1 core
  ids          basket.vouchers-expiry · basket.vouchers
```

Ask: approve, change, or talk it through. Every YOUR CALL needs an answer; fold each answer into the proposal and show it again.

Who signs, by value tier:

| Tier | Signs off |
|---|---|
| critical | the person, always; nothing hands this to you |
| core | the person, by default |
| supporting | you, only if the person has said you may (ask once per repository, never per change) |

On approval, record it with the person's name: `use_cases_apply` with the same `remove` and `save`, and `approved_by` set to their name. Record only what they approved, exactly as they saw it. Approve supporting use cases in your own name only where they said you may.

**Check:** the apply succeeds, and `use_cases_show` reads `approval` `approved` for each saved use case.

## 6. Test first: red, can it fail, green, refactor

**Red.** Write the tests, each inside a validation marker (`<use case id>#<route id>.<name>`), as `use-cases docs linking` shows. If `use-cases-bridge.yml` has no command that runs them, propose one to the person and add it only on their yes. Then run `use_cases_verify_tests` with `step` `run`.

**Check:** `use_cases_links` lists the tests as validation links, and `use_cases_status` for the use case shows the route **failed**. **Error**, a run error, or "its test didn't run" is not red: fix the build, the report or the marker, and run again.

**Can it fail?** Where a test passes before the change (common when extending existing behaviour), plant a small defect in the code it tests, run again, then revert it.

**Check:** the route turns **failed** with the defect, and the defect is gone afterwards.

**Green.** Write the code, inside implementation markers (`<use case id>#<name>`), and run again.

**Check:** `use_cases_links` lists the code as an implementation link, and the use case shows **verified**.

**Refactor.** Reshape the code. When code moves, move its markers with it.

**Check:** still **verified**, with the same links, and `use_cases_status` shows no "marked region is empty" warning.

When your code touches marked code of another use case, or adds behaviour no use case covers, say so and go back to step 4. Never leave a use case quietly out of date.

## 7. See it

Anything the person will see is performed the way they will use it: use the showcase skill. "Change X" after a showcase is the normal path back to step 4, not a failure.

## 8. Prove

Run the CI recipe: `use_cases_verify_tests` with `step` `run`, then the gate, `use_cases_status` with `gate` true (`strict` true on a release branch).

**Check:** `gate.passed` is true. Then show the person the results, `use_cases_render` with `kind` `results` and the same proposal:

```text
RESULTS · Vouchers at checkout

  ✓ Refuse an expired voucher code   unit-tests ✓
  gate   passes
  ids    basket.vouchers-expiry
```

## Never

- Never write or edit `approved` yourself; never approve what the person did not approve, or in their name without their yes.
- Never settle a conflict yourself.
- Never call a step done without its check's output.
- Never treat an error or a run error as red.
- Never put code inside a validation marker, or tests inside an implementation marker: the marker's form decides its role.
- Never hand-write use case YAML when `use_cases_save` or `use_cases_apply` can make the change; they keep the layout and refuse anything invalid.
- Never commit `.use-cases/`, and never copy verdicts between checkouts.
