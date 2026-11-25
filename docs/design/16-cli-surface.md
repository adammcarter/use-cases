# 16 — CLI Surface

**Phase:** 3 — Core Experience  
**Status:** Specification (locked)

## 1. Purpose

`use-cases` is the one command-line surface people, CI, git hooks and agents use. Init (chapter 17), hooks (chapter 18) and CI recipes (chapter 19) are built from these commands.

The chapter fixes what scripts and tools depend on: the commands, the `--json` output, the exit codes and how the workspace is found. Human-readable output is for people and may change freely.

## 2. Commands

```text
use-cases                                    same as use-cases --help
use-cases --help | --version

use-cases validate                           are the authored files right? runs no test, writes nothing
use-cases status [<use case or prefix>]      every use case, worst first; one use case in detail
                 [--group G] [--state S,…]   filters
                 [--gate [--strict]]         does anything block? (section 10)
use-cases verify --start | --finish | --run | --abort     get verdicts from tests (chapter 13)
                 [--only V,…] [--run-id ID]
use-cases record <use case> <route> <status> [message] [--attach F…]
use-cases record --interactive [--attach F…]  asks for each value (section 12)
use-cases links [<use case or prefix>]       which code each use case is tied to
use-cases search [words] | --like F|-       find use cases, best match first, in pages (section 15)
                 [--under P] [--group G] [--tier T,…] [--state S,…] [--in FIELDS]
                 [--exact] [--full] [--page-size N]   |   --next TOKEN
use-cases show <use case>                    one use case, whole (section 14)
use-cases save --file F|- [--dry-run]        create or replace one use case, whole (section 14)
use-cases remove <use case> [--dry-run]      take one use case out (section 14)
use-cases apply --file F|- [--approved-by NAME] [--dry-run]
                                             a batch, all or nothing: delete, then add, then update (section 14)
use-cases approve <use case>… | --all --by NAME [--dry-run]
                                             record a sign-off of each promise as it reads now (section 14)
use-cases init [--minimal] [--prefix P] [--hooks H] [--no-input] [--dry-run]
                                             set up a repository; asks, in a terminal (chapter 17)
use-cases hooks [add | remove commit|push] [--dry-run]
                                             opt-in git hooks for this clone (chapter 18)
use-cases prune [--dry-run]                  remove runs status no longer uses; a person's call (section 20)
use-cases render intent|brief|proposal|results --file F|-
                                             a canonical layout for the person (chapter 21 §7)
use-cases docs [<guide> | words]             the guides that ship with this version (section 16)
               [--exact] [--page-size N]  |  --next TOKEN
use-cases mcp                                the MCP server an agent's host starts; not typed by people (chapter 20)

every command:  --json   one JSON document on stdout (section 5)
                --quiet  no hint line (section 18)
                --workspace DIR   the workspace root, instead of finding it (section 3)
```

Plain `use-cases verify`, with no step, runs nothing: it names the steps and exits 2.

## 3. Finding the workspace

Without `--workspace`, the command starts in the current folder and walks up until it finds a `use-cases.yml` that says `root: true`. That folder is the workspace. A child scope's `use-cases.yml` (no `root: true`) is passed over on the way up.

```text
repo/                  use-cases.yml   root: true    ◀── found from anywhere below
repo/services/pay/     use-cases.yml   (child scope)     passed over
repo/services/pay/src/                                   you are here
```

A workspace nested inside another (its own `root: true`, chapter 04) is found first from inside it, so it is always handled as its own workspace.

No root found: exit 2, "no use-cases.yml with root: true in this folder or any folder above it; run `use-cases init`".

`--workspace DIR` names the root directly. A folder whose `use-cases.yml` is not the root is refused, as chapter 09 requires.

## 4. Output: people first

Without `--json`, every command writes for a person reading a terminal:

- one line per use case, worst first;
- a symbol and a word for every status, never a symbol alone;
- a short reason beside anything that is not verified;
- errors on stderr, as `error: <message>`;
- at most one hint line, last (section 18).

Human output is not a contract. Its wording and layout may change in any release; a script must use `--json`.

## 5. The JSON contract

With `--json`, stdout holds exactly one JSON document, for success and for failure alike. Nothing else is written to stdout. Messages for people still go to stderr.

Every document carries two fields:

```text
output_version = 1
command          validate | status | verify | record | links | search | show | save | remove | apply | approve | render | init | hooks | prune | docs | version,
                 or null when the command itself was not recognised
```

A failed request has the same two fields plus `error`:

```json
{"output_version": 1, "command": "status", "error": {"kind": "invalid", "message": "use-cases/login.yml: …"}}
```

| `error.kind` | Meaning |
|---|---|
| `usage` | the command line itself is wrong: unknown flag, missing argument, bad combination |
| `invalid` | the workspace is INVALID: a use case, groups, bridge settings or link problem |
| `refused` | a valid request that cannot proceed now: no started run, a run locked by another process, bridge settings changed since `--start` |
| `storage` | the results store cannot be read or written safely |
| `cancelled` | the request was stopped by Ctrl-C, SIGTERM or a closed terminal (exit 130, not 2); `verify --finish` and `verify --run` tell it as the sealed run once one exists (section 6) |

The shapes are published as schemas in `docs/schemas/output/` and every output is checked against them. They evolve like contract 1 (ADR 015): a later version only adds optional fields, readers ignore fields they do not know, and `output_version` changes only for a shape that cannot be read that way.

## 6. Exit codes

```text
0     done
1     done, and something needs you: the gate is blocked (section 10),
      or a verify run was sealed with run errors (chapter 13)
2     refused: usage, an INVALID workspace, a request that cannot proceed, or a storage error
130   cancelled (Ctrl-C, SIGTERM or a closed terminal); a verify run is sealed as interrupted
```

Every command uses the same codes. A cancelled command under `--json` still prints its one document: an `error` of kind `cancelled`, exit 130. `verify --finish` and `verify --run` print the sealed run instead, with `cancelled: true`, once a run exists to seal. A failed test is not an exit 1 for `verify`: the run did its job and recorded the verdict. Whether a verdict blocks is the gate's question, asked in one place.

## 7. `use-cases`, `--help`, `--version`

`use-cases` alone and `use-cases --help` print the command list of section 2 and exit 0. `use-cases <command> --help` prints that command's flags.

`use-cases --version` prints the version. With `--json`:

```json
{"output_version": 1, "command": "version", "version": "0.1.0", "contract": 1, "store": 1}
```

`contract` is the transformer contract version (chapter 10) and `store` the run version the core writes (chapter 12).

## 8. `use-cases validate`

Loads the workspace exactly as every other command does (chapter 09) and reports the result. Runs no test and writes nothing, so it is safe on every save, commit and pull request.

```text
$ use-cases validate
✓ valid · 12 use cases (10 ready, 2 draft) · 31 links · 14 files
→ use-cases status
```

An INVALID workspace exits 2 with the problem. Warnings (the marker and link warnings of chapter 08, chapter 10 §18, groups) are listed and never fail it. A use case's missing-link warnings are not among them: they belong to `status` (§9).

The `links` count counts link keys (chapter 08): one per marker region, manual binding or transformer link.

## 9. `use-cases status`

```text
$ use-cases status
✗ failed      checkout.pay.card          unit-tests failed (run 0192f0c4 via unit-tests)
! error       checkout.pay.wallet        unit-tests error (run 0192f0c4 via unit-tests)
○ unverified  shop.login.remember-me     unit-tests: no verdict yet
~ stale       checkout.pay.refund        unit-tests: changed since run 0191aa02
✓ verified    shop.login.authenticate
· draft       shop.cart.share            missing: intent

6 use cases · 1 failed · 1 error · 1 unverified · 1 stale · 1 verified · 1 draft
results: 12 runs · 450 MB · 7 superseded
→ use-cases status checkout.pay.card   to see why
```

The line after the counts is the results store (chapter 12): how many run folders it holds, sealed or not, and the size of every file under `.use-cases/`. When some sealed runs are superseded (chapter 12 §31), it says how many, and when nothing else wants the hint, the hint is `use-cases prune`. A store with no run has no line. With `--json`, `store` holds the same: `runs`, `bytes` and `superseded`, absent when the store has no run. The line is in the list, the one-line view and `--json`, never in the detail view or the gate, which do not measure the store.

Order is worst first (chapter 07's order, reversed): failed, error, incomplete, unverified, stale, verified. Then drafts, then by id.

Verdicts are like test results: each checkout gets its own by running, and none are carried between checkouts or from CI. In a checkout where nothing has run yet, `unverified` means no verdict here, never failed, so plain `status` says that in one line instead of listing every use case:

```text
$ use-cases status
no verdicts in this checkout yet: 109 use cases (3 draft), none run here
→ use-cases verify --run   for a baseline, if you want one
```

A run that never finished still counts toward the store's line, which then follows the one line.

The count is of READY use cases, with the drafts after it in parentheses, and `(D draft)` is left out when there are none. The hint is `verify --run` when some validation has a run command, otherwise `verify --start`.

A baseline is optional, as running the tests after a clone is: the repo's CI may already guarantee them. Every filtered or detailed view, and `--json`, lists as usual.

A use case whose promise changed after its sign-off says so on its line, `changed since approved`, and the detail view shows its sign-off (`not approved` only where `sign_off: required`). A marked region left empty, the sign its code has moved (chapter 08), is a warning under the list, in the one-line status too, and in the use case's detail. A run that never finished is a workspace warning under the list too, `run <id> never finished` (chapter 12 §22). So is every link or resource warning no single use case owns (an overlap, a link into excluded content): the warnings `validate` lists are never hidden from `status`. With `--json`, every use case has `approval` (`approved`, `changed` or `unapproved`, chapter 21) and every READY one its `value_tier`.

| Form | Shows |
|---|---|
| `status` | every use case |
| `status checkout.pay.card` | that use case in detail: every route, whether it gates, its status and why |
| `status checkout.pay` | an id prefix: the use cases under it, one line each |
| `status --group release` | the members of a group (chapter 03) |
| `status --state failed,stale` | only those states; `draft` is a state here |

An exact use case id always wins over a prefix. A target that names no use case or id prefix is a usage refusal (exit 2). Filters combine: `status checkout --state stale`.

A use case with no implementation links, or a gating route with no validation links and no procedure, is warned about with that use case: in its detail view (`status <use case>`) and in its `warnings` in `--json`, never in the list, which stays one line per use case (chapter 08). `validate` and `links` do not list these warnings.

```text
$ use-cases status checkout.pay.card
✗ failed  checkout.pay.card · Pay by card

  route          gates   status          why
  unit-tests     yes     ✗ failed        run 0192f0c4 via unit-tests
  manual-check   no      ○ unverified    no verdict yet

→ use-cases verify --run   once it is fixed
```

The "why" is chapter 15's explanation for the route: the run that decided it, the run diagnostic ("its test didn't run", "code changed during the run"), or the run it has changed since. Human output shortens a run id to the shortest prefix of at least 8 digits that names only one run in the store, so two runs started within the same minute still show different ids; `--json` always has all 32. Commands that take a run id take all 32 digits.

## 10. The gate

`use-cases status --gate` answers "does anything block?", for a whole workspace or one group (`--gate --group release`). It exits 1 when something blocks.

| Use case status | Default | `--strict` |
|---|---|---|
| failed | blocks | blocks |
| error | blocks | blocks |
| stale | blocks | blocks |
| incomplete | warns | blocks |
| unverified | warns | blocks |
| verified | passes | passes |

- An INVALID workspace blocks: the command exits 2.
- A use case's status is the worst of its gating routes (chapter 07). A route with `gates_verification: false` never blocks.
- DRAFT use cases never block, in either mode: they have no verification status yet.
- The default means nothing that was proven may quietly stop being proven. `--strict`, for release branches, means everything must be proven.

**Sign-off.** With `sign_off: required` in the root `use-cases.yml` (chapter 04), the gate also holds a READY use case whose promise is not approved as it reads now (chapter 21):

| Not approved, or changed since approved | Default | `--strict` |
|---|---|---|
| critical | blocks | blocks |
| core | warns | blocks |
| supporting | warns | blocks |

- Drafts never block, here either.
- Without `sign_off: required`, approvals are recorded and shown, and never gate.
- In `--json`, a gate entry held for its sign-off has `approval` (`changed` or `unapproved`).

```text
$ use-cases status --gate
~ stale       shop.cart.share        unit-tests: changed since run 0191aa02 · changed since approved
✓ verified    shop.login.hint        (warning: not approved)
✓ verified    shop.login.lockout     (not approved)

gate: blocked · 2 block (1 stale, 1 not approved) · 1 warning (1 not approved)
→ use-cases status shop.cart.share
```

```text
$ use-cases status --gate
✗ failed      checkout.pay.card          unit-tests failed (run 0192f0c4 via unit-tests)
○ unverified  shop.login.remember-me     unit-tests: no verdict yet   (warning)
~ stale       checkout.pay.refund        unit-tests: changed since run 0191aa02

gate: blocked · 2 block (1 failed, 1 stale) · 1 warning (1 unverified)
→ use-cases status checkout.pay.card
```

`--gate` considers every use case in its scope, so it cannot be combined with `--state` or an id argument (exit 2, usage).

## 11. `use-cases verify`

The flow is chapter 13's. The command line adds only what a person sees:

```text
$ use-cases verify --start
started run 0192f0c4e5a17c3e9b04d2f61a8c3b57
  unit-tests   write the report to /work/shop/.use-cases/runs/0192f0c4…/reports/unit-tests/results.xml
→ run your tests, then: use-cases verify --finish --run-id 0192f0c4e5a17c3e9b04d2f61a8c3b57

$ use-cases verify --finish
run 0192f0c4 · 5 verdicts (4 pass, 1 fail) · 0 run errors
→ use-cases status --gate
```

When tests ran that sit inside no link (chapter 15 §6), the summary line ends with `· N not tied to a use case`, and a block headed `test not tied to a use case` follows the run errors: one line per test, `file:line  status  name`, the worst status first. The block lists every test, however many, so a lost link is never hidden; `--json` has them as `unlinked_tests`.

With `--json`, `--start` returns the run id and each `{report}` path, `--finish` and `--run` return the sealed run (its manifest fields and results, as in chapter 12), and `--abort` the run it closed.

Exit 1 when the run was sealed with run errors (a missing report, a build failure, a transformer error): CI stops there, and the verdicts that were judged are still stored.

## 12. `use-cases record`

```text
use-cases record shop.login.authenticate manual-login-check pass "checked on staging"
```

Given all its values, `record` stores the verdict (chapter 13 §12). Given too few, it refuses with exit 2 and names what is missing:

```text
error: record needs <use case> <route> <status>; missing: route, status
→ use-cases record --interactive   to be asked for each
```

`--interactive` asks for each value instead:

```text
$ use-cases record --interactive
Use case?  1 shop.login.authenticate   2 shop.login.remember-me   …
           > 1
Route?     1 unit-tests   2 manual-login-check
           > 2
           Steps: 1. Enter valid credentials.  2. Submit.
Result?    pass / fail / incomplete / error
           > pass
Note?      (optional) > checked on staging
recorded: shop.login.authenticate / manual-login-check → pass
```

- Use cases and routes may be given by number (`--interactive` only), id, or an unambiguous prefix of the id's characters, with or without `--interactive`: an exact id wins, several matches are a usage refusal that lists them. A prefix here is an abbreviation of one id, unlike a `status` or `links` target, which selects a group by whole segments.
- Only READY use cases are offered; a route's procedure steps are shown when it has them.
- `--interactive` needs a terminal. Without one (CI, a pipe, `--json`), it is refused with exit 2 and never waits for input.
- Asking is opt-in for `record`, which is run again and again, often from scripts. `init` is the one exception: run once, by a person, it asks by default in a terminal (chapter 17). Neither ever asks outside a terminal.
- `--attach` works in both forms.

## 13. `use-cases links`

Lists every link, or those of one use case or id prefix: its use case, role, file and lines. With `--json`, each link has exactly the shape a transformer receives (chapter 10): lines, never bytes. A link that covers a whole file runs from line 1 to the last line holding any bytes; an empty file is 1 to 1.

A target that names no use case or id prefix is a usage refusal (exit 2), as for `status`; an exact use case id wins over a prefix. The target narrows the links, never the diagnostics: every problem in the workspace is shown whatever the target.

The links document is ordered by use case id, then route (implementation links first), then binding id, then file (UTF-8 bytes), then start line as a number.

## 14. `use-cases show`, `save`, `remove`, `apply`

The authored YAML is the truth, and people edit it by hand. These three commands let a script or an agent change use cases without writing YAML, and they follow the same rules as a person's edit.

```text
show <use case>          one use case, whole: its full id and every field
save --file F|-          create or replace one use case, whole: a YAML or JSON file, or - for stdin
remove <use case>        take one use case out
apply --file F|-         a batch of the two: all of it, or none of it
```

`show --json` gives the use case as `definition`, exactly what `save` accepts: show, change a field, save. It always carries the use case's `approval`. Plain `show` prints a `# file · state` line and then the use case as YAML, exactly as `save` would write it.

```json
{
  "output_version": 1,
  "command": "show",
  "use_case": "invoicing.billing.discounts",
  "file": "use-cases/billing.yml",
  "state": "READY",
  "missing": [],
  "definition": {
    "id": "invoicing.billing.discounts",
    "title": "Discounts never make a total negative",
    "value_tier": "core",
    "intent": "A discount larger than the invoice brings it to zero, never below.",
    "scenarios": [{"id": "capped-at-zero", "when": ["A 5.00 discount is applied to a 3.00 invoice."], "then": ["The total is 0.00."]}],
    "validation": [{"id": "unit-tests", "type": {"kind": "unit"}, "covers": ["capped-at-zero"]}]
  }
}
```

**One use case changes, nothing else.** Only that use case's lines in its file are rewritten. Every other use case, comment and blank line in the file stays exactly as it was. Comments inside the use case being replaced cannot follow its new fields, so they are dropped and each one is listed as a warning, in `--dry-run` too: never silently. `save`, `remove` and `apply` refuse a workspace that is already INVALID, as every command does (chapter 09); fix it by hand first. Fields are written in the order people read them (id, title, value tier, intent, scenarios, validation, bindings), with short lists and small mappings on one line (`when: [x]`, `type: { kind: unit }`), as in the chapters' examples. Text of more than one line is written as a `|` block, as people write it by hand, and text that a common YAML reader would read as something other than text is quoted (chapter 09).

**Where a new use case goes.** The recommended structure (chapter 04) decides, and nothing else can:

```text
the use case's group already has a file   → added to that file
no file for the group yet                 → a new file, at the path the structure gives:
                                            invoicing.refunds.partial  → use-cases/refunds.yml       prefix: refunds
                                            invoicing.payments.card.x  → use-cases/payments/card.yml prefix: payments.card
                                            in a child scope, inside that scope's use_cases_dir
```

A use case needs a group: an id with no group, or straight under a scope's namespace, is refused. A file already at the structured path that holds another group is refused, never taken over.

**Nothing invalid is ever written.** Before anything is written, the whole workspace is loaded as it would be after the change (chapter 09). A change that would leave it INVALID is refused with exit 2 and writes nothing: a missing field, an unknown one, a validation covering a scenario that does not exist, or removing a use case a group names by id.

**Remove.** The use case's lines go; when it was the last in its file, the file goes too. Its verdicts stay in the store: a remove never deletes evidence (chapter 12). Markers that still name the use case are listed as warnings:

```text
$ use-cases remove invoicing.billing.tax-regions
removed: invoicing.billing.tax-regions
update  use-cases/billing.yml
warning: tests/test_tax.py:9-11 is still marked for invoicing.billing.tax-regions
```

`save` and `remove` return what they did: `action` (`created`, `added`, `replaced`, `unchanged` or `removed`), the `file`, and each file `changes` touched (`create`, `replace` or `delete`). A save that changes nothing is `unchanged` and writes nothing.

```json
{
  "output_version": 1,
  "command": "save",
  "use_case": "invoicing.refunds.partial",
  "file": "use-cases/refunds.yml",
  "action": "created",
  "changes": [{"path": "use-cases/refunds.yml", "action": "create"}],
  "warnings": [],
  "dry_run": false
}
```

**A sign-off.** `approve` records that a person approved a use case's promise as it reads now: on the use case itself, as `approved` (chapter 02), with their name, today's date and a fingerprint of the promise.

```text
$ use-cases approve shop.login.lockout --by Sam
approved  shop.login.lockout

update  use-cases/login.yml
```

- `--by` is required: the core has no notion of users, and the name is what the person reviewing the commit sees.
- `--all` approves every use case as it reads now: how a workspace adopting sign-off catches up, in one commit.
- A use case already approved as it reads now is `unchanged`.
- With no use case to approve (`--all` in a workspace that has none), it says `nothing needs approval`, with or without `--dry-run`.
- `save` never writes an approval: a save without one keeps the approval the use case had, so a changed promise reads `changed since approved`; a save that brings a different one is refused.
- Only the use case's `approved` field is written: every other line of the file stays as it was. A comment inside an `approved` field that is written again is dropped and listed as a warning.
- With `--json`: `by`, and each use case with its `file` and `action` (`approved` or `unchanged`), with `changes`, `warnings` and `dry_run`.

**A batch.** One request often means several changes together: replace one use case, extend another, add a third. `apply` takes them as one batch and applies all of them, or none:

```yaml
remove:
  - shop.share.email
save:
  - id: shop.share.link
    title: Share by link
  - id: shop.login.lockout
    title: Lock an account after failed attempts
```

- **One fixed order, whatever order the file is in:** every removal, then every addition, then every update. The core decides from each id whether a save adds or updates, so a batch can never claim to add something that exists.
- **Each use case at most once in a batch.** Removing and saving the same id would be ambiguous; that is an update.
- **Checked once, as a whole.** Every change is made to the files as the changes before it left them, and the finished result is loaded as the workspace would be; a replace can never fail halfway. Anything INVALID, and nothing is written.
- **The dry run is what is signed off** (chapter 21): `--dry-run` lists every change in the order it runs, and exactly that batch is what `apply` writes.
- A file several changes touch is written once.
- `--approved-by NAME`: the batch was signed off, so each use case it saves is approved as it now reads, in the same write. A use case already approved as it now reads keeps the sign-off it has and is `unchanged`, as `approve` leaves it.

```text
$ use-cases apply --file batch.yml --dry-run
would delete  shop.share.email
would add     shop.share.link
would update  shop.login.lockout

would update  use-cases/login.yml
would update  use-cases/share.yml
```

With `--json`, `use_cases` lists what happened to each use case in that order (`removed`, `created`, `added`, `replaced` or `unchanged`), with `changes`, `warnings` and `dry_run` as for `save` and `remove`:

```json
{
  "output_version": 1,
  "command": "apply",
  "use_cases": [
    {"use_case": "shop.share.email", "file": "use-cases/share.yml", "action": "removed"},
    {"use_case": "shop.share.link", "file": "use-cases/share.yml", "action": "added"},
    {"use_case": "shop.login.lockout", "file": "use-cases/login.yml", "action": "replaced"}
  ],
  "changes": [{"path": "use-cases/login.yml", "action": "replace"}, {"path": "use-cases/share.yml", "action": "replace"}],
  "warnings": [],
  "dry_run": true
}
```

## 15. `use-cases search`

Finds use cases: by words, or by likeness to a whole use case. It is how a person or an agent checks what already exists before adding something. It is also how overlapping use cases are found: `--like` with one use case lists the ones most like it, and any that exclude it in their out of scope say so. Search is one pipeline, and every option belongs to exactly one stage, so a new filter or field later joins its stage and changes nothing else:

```text
query ──▶ which use cases ──▶ which fields ──▶ match + rank ──▶ page ──▶ results
          --under --group      --in             words | --like    --page-size
          --tier --state                        --exact           --next
```

**The query.**

| You type | Means |
|---|---|
| `double tap` | use cases with these words, best first; case ignored |
| `"double tap"` | this exact phrase must appear (`double-tap` counts: punctuation is not a word) |
| `-zoom`, `-"to zoom"` | leave out anything with this word or phrase |
| `--exact` | only whole words exactly as typed |

Without `--exact`, a word also matches words it starts (`lik` finds `like`) and small typos: one wrong, missing, extra or swapped letter for a word of 4 letters or more, two for 8 or more. The query is one argument, or several joined with spaces; put `--` before one that starts with `-` (`use-cases search -- "-zoom double"`).

**`--like F|-`** takes a whole use case instead of words, a file or `-` for stdin, exactly as `save` takes one (section 14). Its title, intent, scenarios and out of scope are the query, and its own id is never a result. It need not be valid: a draft is enough. Words or `--like`, never both.

**Which use cases.** Filters keep only what they name. Across flags every filter must hold (AND); inside one flag, any value may (OR):

| Flag | Keeps |
|---|---|
| `--under checkout.pay` | use cases under an id prefix |
| `--group release` | the members of a group (chapter 03) |
| `--tier critical,core` | those value tiers |
| `--state failed,stale,draft` | those states, as `status` shows them |

**Which fields.** `--in` names the parts of a use case searched: `id`, `title`, `description`, `intent`, `scenarios` (their ids, given, when and then), `out_of_scope`, `validation` (route ids and procedure steps). The default is all. A match in the id or title counts most, then description and intent, then the rest.

**Results.** Best first, ties by id. The same search on the same files always gives the same order.

```text
$ use-cases search "double tap"
○ unverified  app.feed.post.like    Double tap to like a post  title: "Double tap to like a post"
○ unverified  app.feed.media.zoom   Zoom a photo               out of scope: "Double tap to zoom"
○ unverified  app.feed.post.unlike  Undo a like                scenario main: "The user double-taps a liked post again"

3 matches
→ use-cases show app.feed.post.like
```

Each match carries its id, title, file, status and value tier, a `score`, and `why`: every place it matched, with the field, the scenario or route, and the text. A match in `out_of_scope` is always in `why`, and people see "also out of scope" when it is not the first reason: it says the use case explicitly excludes this. `--full` adds each match's whole use case, exactly as `show` returns it.

`score` is between 0 and 1, for ordering one search's results. It is not comparable between searches and not a contract: how it is worked out may improve, and a helper that ranks by meaning may be added beside the core later, giving the same shape.

**Pages.** 20 matches a page by default, `--page-size N` from 1 to 100. Every page says how many match in all (`total`) and how many come before it (`offset`). When more follow, `next` is a token: `use-cases search --next <token>`, passed alone, gives the following page.

- The token carries the whole search: query, filters, fields and position. Passing anything else with it is refused (exit 2), so a later page can never mix in different options.
- Nothing is kept between calls. The token holds a digest of what the search saw: the use cases, their statuses and the group's members. If any of them changed, the next page is refused ("use cases changed since this search; search again") rather than skipping or repeating a match.
- A token is not secret. One that was edited or not made by `search` is refused.

`use-cases search "double tap" --page-size 1 --json` gives the first page, and the token for the next:

```json
{
  "output_version": 1,
  "command": "search",
  "total": 3,
  "offset": 0,
  "page_size": 1,
  "matches": [
    {
      "use_case": "app.feed.post.like",
      "title": "Double tap to like a post",
      "file": "use-cases/feed/post.yml",
      "status": "unverified",
      "value_tier": "critical",
      "score": 1.0,
      "why": [
        {"field": "title", "text": "Double tap to like a post"},
        {"field": "intent", "text": "Double tap to like a post."},
        {"field": "scenarios", "where": "main", "text": "The user taps a post twice"}
      ]
    }
  ],
  "next": "eNodjcsKwjAQAH9F9txD83Kz_RnZbDYqiImmLaj47waP"
}
```

No match is not an error: exit 0 with no matches. A search with nothing to look for (no words, or only `-words`) is refused, exit 2.

## 16. `use-cases docs`

The guides that ship with the tool: one short page per task, written for whoever is using this version, so they always match what is installed. `docs` needs no workspace: it is about the tool, and works before `init`.

```text
use-cases docs                     the list of guides
use-cases docs <guide>             one guide, whole
use-cases docs markers stale       the sections that match, best first
```

| Guide | Covers |
|---|---|
| `getting-started` | init, a first use case, first status |
| `writing-use-cases` | the fields, READY vs DRAFT, value tiers, the file layout, show / save / remove |
| `finding` | search, and `--like` before adding one |
| `linking` | markers and manual bindings |
| `verifying` | verify `--run` / `--start` / `--finish`, record, the gate, pruning the store |
| `reading-status` | each state, what "stale" means, the results store's line |
| `ci-and-hooks` | the two-step CI recipe, the opt-in hooks |
| `quirks` | the gotchas: validate vs verify, unverified means no verdict here (never failed), YAML values that need quotes, `--next` passed alone, remove keeps evidence, marker text kept as data |

- A guide is one Markdown page: a title, a first paragraph saying what it covers, then short `##` sections that each stand alone.
- **One result is one section**, so an agent gets its answer without reading a whole guide. Words are matched and ranked exactly as `search` matches them (section 15): typos, `"phrases"`, `-words`, `--exact`. A match in a section's heading counts most.
- A guide's exact name shows that guide, as an exact id wins in `status`.
- Pages work as in `search`: `--page-size`, and `--next <token>` passed alone.
- **The guides are held true:** every command and flag a guide names must exist, and a test checks it.

With `--json`, `view` says which of the three answers it is: `list` (each guide's name, title and what it covers), `guide` (its name, title and text), or `search` (one page of sections, shaped like a search page, each with its guide, section, text and score). `use-cases docs stale --json` gives:

```json
{
  "output_version": 1,
  "command": "docs",
  "view": "search",
  "total": 12,
  "offset": 0,
  "page_size": 20,
  "matches": [
    {"guide": "reading-status", "section": "Reading status", "text": "Each state a use case can be in, what \"stale\" means, which states block the gate, and what to do about each.", "score": 0.3},
    {"guide": "reading-status", "section": "The list", "text": "```text $ use-cases status ✗ failed basket.discounts unit-tests failed (run 01a2057f via unit-tests) · draft example.getting-started missing: value_tier 2 use c", "score": 0.3},
    {"guide": "reading-status", "section": "The results store", "text": "Every run keeps a folder in `.use-cases/`, and nothing is deleted on its own, so the store grows. The `results:` line under the list says how many runs it holds", "score": 0.3},
    {"guide": "reading-status", "section": "What each status means", "text": "| Status | Means | What to do | |---|---|---| | `✗ failed` | a test or a person said it does not work | fix the code (or the use case), then run again | | `! er", "score": 0.3},
    {"guide": "reading-status", "section": "When a verdict goes out of date", "text": "A verdict belongs to exactly what was proven. It goes `stale` when any of these change: - the code inside an implementation marker or binding; - the test inside", "score": 0.3},
    {"guide": "reading-status", "section": "One use case in detail", "text": "```text $ use-cases status basket.discounts ~ stale basket.discounts · Discounts never make a total negative route gates status why unit-tests yes ~ stale chang", "score": 0.3},
    {"guide": "reading-status", "section": "Only some use cases", "text": "| Command | Shows | |---|---| | `use-cases status basket` | the use cases under an id prefix | | `use-cases status --group smoke` | the members of a group | | `", "score": 0.3},
    {"guide": "reading-status", "section": "The gate", "text": "`use-cases status --gate` answers \"does anything block?\" and exits 1 when something does. `--strict`, for release branches, means everything must be proven: | S", "score": 0.3},
    {"guide": "ci-and-hooks", "section": "Fresh every run", "text": "A CI job starts from a clean checkout with no `.use-cases/`, and the gate judges only what that job's run proved: - a use case whose tests ran has this run's ve", "score": 0.3},
    {"guide": "quirks", "section": "Changing a use case's words puts its verdict out of date", "text": "Changing its intent, a scenario a route covers, or the route itself makes that route `stale`, as changing its code does. Its title, description, value tier and ", "score": 0.3},
    {"guide": "finding", "section": "Narrow it down", "text": "| Flag | Keeps | |---|---| | `--under basket` | use cases under an id prefix | | `--group smoke` | the members of a group | | `--tier critical,core` | those val", "score": 0.135},
    {"guide": "finding", "section": "For agents", "text": "The `use_cases_search` tool takes `query` (words) or `like` (a whole use case, as an object), the filters `under` and `group` (each one text) and `tier`, `state", "score": 0.135}
  ],
  "next": null
}
```

## 17. `--dry-run`

`save`, `remove`, `apply`, `approve`, `init` and `hooks` change files you own, and `prune` removes runs; all of them take `--dry-run`: the command does everything but write. It checks the change exactly as the real run does, refuses what the real run would refuse, and returns the same document with `dry_run: true`. People see "would":

```text
$ use-cases save --file refund.yml --dry-run
would save: invoicing.refunds.partial (created)
would create  use-cases/refunds.yml
```

`hooks` says it the same way: a hook it would add reads `would install`, one it would take out `would remove` (chapter 18 §5). So does `prune`: `would remove` for each run (section 20).

A preview can never differ from the real run: both plan the change first, and only the real run writes the plan. `validate`, `status` and `links` write nothing already. `verify` and `record` only ever add to the results store (chapter 12), so they have no `--dry-run`.

## 18. Hints

Human output may end with one hint line: the command a person most likely wants next, prefixed `→`. Never more than one, always last, never in `--json`, and `--quiet` removes it. The wording is not a contract.

| After | The hint points to |
|---|---|
| `status` with something failed, in error or incomplete | `status <that use case>` |
| `status` with only stale or unverified | `verify --run`, or `verify --start` when no validation has a run command |
| `status` with neither, and superseded runs in the store | `prune` |
| `status --gate` blocked | `status <the first blocking use case>` |
| `verify --start` | running the tests, then `verify --finish --run-id <id>` |
| `verify --finish` or `--run` | `status --gate` |
| `validate` | `status` |
| `record` | `status <that use case>` |
| `save` | `status <that use case>` |
| `search` | `search --next <token>` when more follow, else `show <the best match>` |
| `docs` | `docs <guide>`: the list's, or the best match's |
| a missing `record` value | `record --interactive` |
| `hooks`, with a hook not installed | `hooks add <it>` |

## 19. Symbols and colour

| Status | Symbol |
|---|---|
| failed | ✗ |
| error | ! |
| stale | ~ |
| incomplete | ◐ |
| unverified | ○ |
| verified | ✓ |
| draft | · |

A symbol is always followed by its word, so nothing depends on the symbol or its colour. Colour is used only when stdout is a terminal, and never when `NO_COLOR` is set.

## 20. `use-cases prune`

Removes the sealed runs a later run has superseded and that `status` does not use for the workspace as it is now (chapter 12 §31), so the results store stops growing without bound. It is a person's decision: deleting evidence is never done by a run, by another command or by an agent tool (chapter 20). It loads and judges the workspace as `status` does, so an INVALID workspace is refused the same way (exit 2) and nothing is removed.

```text
$ use-cases prune
removed  run 01a20e8224b8b82ea0fdc1e39430a016  7.8 KB
removed  run 01a20e8227b82ec00ca52da7c0ff9a9d  1.2 MB

removed 2 runs · freed 1.2 MB
```

`--dry-run` lists the same runs and removes nothing:

```text
$ use-cases prune --dry-run
would remove  run 01a20e8224b8b82ea0fdc1e39430a016  7.8 KB

would remove 1 run · would free 7.8 KB
```

A folder an interrupted prune left behind (chapter 12 §31) is removed too, on its own line: `removed leftover  .use-cases/runs/.tmp-prune-<id>  7.8 KB`, or `would remove leftover` under `--dry-run`, and counted in the total (`removed 1 run, 1 leftover · freed 1.2 MB`). With nothing superseded and no leftover it says `nothing to prune`. Runs are named by their whole id, since runs started close together share their first digits. A run another process holds, or one the file system refuses to move, is kept with a note (`note: run <id> is in use by another process, so it was kept`) and counted in the total, `kept 1 run`; a prune that removes nothing and keeps some runs says that, never `nothing to prune`. A run moved out of `runs/` whose folder cannot be deleted is counted as `1 run left over`, its space not freed, and the next prune removes it.

**It changes no answer.** For the workspace as it is now, `status` and the gate give the same statuses, counts, gate answer and route notes after a prune as before, wherever the code is. In `status --json` only run IDs and paths, `store`, and the warnings about integrity findings in the removed runs change. What is lost is audit history, and the verdicts for older code states the code later returns to: such a route reads `stale` until it is run again (chapter 12 §31).

An INVALID workspace is refused as `status` refuses it (exit 2, `invalid`), and a store that cannot be read safely is a storage error (exit 2); either way nothing is removed. Otherwise it exits 0, cancelled 130 (section 6).

With `--json`:

```json
{"output_version": 1, "command": "prune", "dry_run": false, "removed": [{"run_id": "01a20e8224b8b82ea0fdc1e39430a016", "bytes": 7812}], "leftovers": [], "kept": [], "left_over": [], "bytes": 7812, "notes": []}
```

`removed` lists each run removed (or that would be, with `dry_run: true`) with the size of its folder in bytes, oldest first; `leftovers` each leftover folder of an interrupted prune, by `folder` and `bytes`; `bytes` is the space those two free. `kept` lists the planned runs still in the store, and `left_over` the runs moved out whose folder could not be deleted; `notes` say why.

## 21. Final model

```text
             ┌─ people ──────────── human output (may change) + one hint
use-cases ───┤
             └─ scripts, CI, agents ─ --json (schemas, versioned) + exit codes 0 · 1 · 2 · 130

validate ─ files only        status ─ look, filter, explain, gate       verify ─ get verdicts
record ─ a manual verdict    links ─ what code is tied to what          init ─ chapter 17
search ─ words or --like; filters · fields · rank · pages
show · save · remove ─ one use case, whole; one file's lines; never INVALID
apply ─ a batch: delete, add, update; all or nothing
approve ─ a sign-off, on the use case, of its promise as it reads now
render ─ the four layouts people read: intent, brief, proposal, results (chapter 21)
--dry-run ─ everything but the write             hooks ─ chapter 18
docs ─ the guides for this version, searched like use cases
prune ─ a person removes superseded runs; no answer of status changes
```
