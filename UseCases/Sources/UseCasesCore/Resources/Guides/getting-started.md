# Getting started

Set up Use Cases in a repository, write a first use case, prove it with a test, and read its status.

## What a use case is

A use case is one behaviour your code promises, written in plain words, together with how that promise is proven. Use cases live in YAML files in your repository, beside the code. The `use-cases` command ties each one to the tests that prove it and the code that does it, runs those tests, and tells you which promises are proven and which are not.

```text
use case (YAML)  ──  what the code promises, and how it is proven
markers (code)   ──  which tests prove it, which code does it
verify           ──  runs the tests and keeps a verdict for each use case
status           ──  what is proven now, worst first
```

## Set up a repository

Run `use-cases init` at the top of the repository:

```text
$ use-cases init
created  use-cases.yml
created  use-cases/example.yml      a DRAFT example: fill it in, or delete it
created  use-case-groups.yml
created  use-cases-bridge.yml       a commented template: add your own test command
added    .use-cases/ to .gitignore
→ use-cases status
```

| File | What it is |
|---|---|
| `use-cases.yml` | marks this folder as the workspace root (`root: true`) |
| `use-cases/example.yml` | a worked example use case, left DRAFT so it never blocks anything; read it, then delete it |
| `use-case-groups.yml` | named sets of use cases, to look at or gate together |
| `use-cases-bridge.yml` | how your tests are run: a commented template you fill in |
| `.use-cases/` | where verdicts are kept; generated, never committed |

- In a terminal, `init` asks a few questions. Outside one (a script, CI, an agent) it asks nothing. `--no-input` makes it ask nothing anywhere.
- `--minimal` writes only `use-cases.yml`. `--prefix shop` puts `shop.` in front of every use case id; choose it once, because changing it later renames every use case.
- `--hooks commit,push` also adds the git hooks (`use-cases docs ci-and-hooks`).
- `--dry-run` shows what it would create and writes nothing.
- It never overwrites. Run it again and every file is listed as `kept`.

`use-cases validate` checks the files at any time. It runs no test and writes nothing:

```text
$ use-cases validate
✓ valid · 1 use case (0 ready, 1 draft) · 0 links · 1 file
→ use-cases status
```

## Write a first use case

Put the file under `use-cases/`. The `prefix` starts every id in the file, so the use case below is `basket.discounts`:

```yaml
prefix: basket
use_cases:
  - id: discounts
    title: Discounts never make a total negative
    value_tier: core
    intent: A discount larger than the basket brings the total to zero, never below.
    scenarios:
      - id: capped-at-zero
        when: [A discount of 5 is applied to a basket of 3.]
        then: [The total is 0.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [capped-at-zero]
```

Once you have read the example, delete `use-cases/example.yml`, and change the prefix the `smoke` group selects in `use-case-groups.yml` from `example` to `basket`; otherwise the tool warns that the group matches nothing.

Every field is explained in `use-cases docs writing-use-cases`. Instead of writing the file by hand, you can hand the use case to `use-cases save --file -` on standard input; it picks the file for you.

## Tell it how to run your tests

`use-cases-bridge.yml` says which command runs the tests and how to read the report the command writes. The tool never guesses this for you.

Example, for a project whose tests are a shell script that writes a JUnit XML report to the path it is given:

```yaml
schema_version: 1

validations:
  - id: unit-tests
    report: results.xml
    run: [sh, tests/total-test.sh, "{report}"]
    transformer: junit
    settings: { find: file-name }
```

`{report}` is replaced by the path where this run's report must be written. The transformer reads that report; `use-cases docs verifying` lists them.

## Mark the test and the code

Put a pair of marker comments around the test that proves a scenario, and around the code that does it. The marker names the use case, then `#`, then the route and a name of your choosing for a test, or just a name for code.

Example, `tests/total-test.sh`: a shell script that runs one test and writes a JUnit XML report to the path it is given, with the test marked:

```sh
#!/bin/sh
# Runs the tests and writes a JUnit XML report to $1.
report=$1
failure=
cd "$(dirname "$0")/.."

# @use-case:basket.discounts#unit-tests.capped-at-zero
test="capped at zero"
[ "$(sh src/total.sh 3 5)" = "0" ] || failure='<failure message="a 5 discount on 3 should be 0"/>'
# @use-case:end basket.discounts#unit-tests.capped-at-zero

printf '<testsuites><testsuite name="total" tests="1"><testcase classname="tests/total-test.sh" name="%s" file="tests/total-test.sh">%s</testcase></testsuite></testsuites>\n' "$test" "$failure" > "$report"
```

The code it tests, `src/total.sh`, with the code marked:

```sh
#!/bin/sh
# Prints the total of a basket after a discount.
# usage: total.sh BASKET DISCOUNT
# @use-case:basket.discounts#never-negative
total=$(( $1 - $2 ))
if [ "$total" -lt 0 ]; then total=0; fi
# @use-case:end basket.discounts#never-negative
echo "$total"
```

`use-cases links` lists what the markers tie to each use case, with the lines between them:

```text
$ use-cases links
basket.discounts  implementation         src/total.sh:5-6
basket.discounts  validation unit-tests  tests/total-test.sh:8-9
```

More in `use-cases docs linking`.

## Get a first verdict

```text
$ use-cases verify --run
run 01a20956 · 1 verdict (1 pass) · 0 run errors
→ use-cases status --gate

$ use-cases status
✓ verified    basket.discounts

1 use case · 1 verified

$ use-cases status --gate
gate: clear
```

A failing test is a verdict, not a failed command: `verify` still exits 0, and `status` shows the use case as failed. `use-cases docs reading-status` explains every status.

## Where to go next

| Guide | For |
|---|---|
| `use-cases docs writing-use-cases` | the fields, READY and DRAFT, adding and changing use cases |
| `use-cases docs finding` | finding what already exists before adding something |
| `use-cases docs linking` | markers and manual bindings |
| `use-cases docs verifying` | running tests, recording a verdict by hand |
| `use-cases docs reading-status` | what each status means, and the gate |
| `use-cases docs ci-and-hooks` | CI and git hooks |
| `use-cases docs quirks` | the things that surprise people |

`use-cases docs` followed by any words searches every guide.
