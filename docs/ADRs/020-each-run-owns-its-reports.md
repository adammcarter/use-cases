# ADR 020: Each run owns its reports, and validate deletes nothing

## Status

Accepted - 2026-09-25

Its command names are superseded by [ADR 021](021-verify-runs-tests-validate-checks-files.md): `validate --start/--finish/--run` is now `verify`, and `--abandon` is `--abort`.

Supersedes the report handling in [ADR 005](005-tests-run-in-the-real-project-between-start-and-finish.md) (the start point deleted old reports), [ADR 007](007-only-the-core-writes-sealed-run-folders.md) (the core copied reports into the run, and no report could be inside `.use-cases/`) and [ADR 019](019-four-statuses-with-fixed-meanings.md) (private report copies, and the rules keeping a report from holding code). The rest of those decisions stands.

## Context

A report was a path in the project, such as `build/use-cases/pytest.xml`. So that a run never read a report left over from an earlier run, `--start` and `--run` deleted whatever was at that path. That in turn needed guards: a report could not hold code, a resource, a use case file or another validation's report, because deleting it would have deleted them too. Transformers read a private copy so the bytes judged matched the bytes sealed.

The owner rejected the deletion outright: "each run should be an additive run, isolated completely", with nothing deleted by a validate, and asked that `.use-cases/runs/<run>/` "contain EVERYTHING needed to be used by the validate command to mark our use cases as passed/not". They also asked that `--run` be built on `--start` and `--finish`, "with the addition that we plugin in the bit between the start and finish commands".

## Decision

- At the start point the core creates `.use-cases/runs/<run-id>/reports/<validation-id>/` for each selected validation. The tests write their report there, and nowhere else is read.
- `{report}` is the absolute path of that folder, or of the file or folder name the bridge settings give inside it. `--start` prints each validation's `{report}`; `--run` puts it into the run commands.
- The bridge's `report` is optional and is a name, never a path: 1 to 64 portable characters, not starting or ending with `.`, and not a Windows device name. Validation ids, now folder names, may not be Windows device names either.
- Nothing is deleted before, during or after a run, and no run touches another run's folder. The one deletion is `use-cases prune`, a person's command (chapter 12 §31).
- The transformer reads the report in place. The core digests the validation's reports folder before and after the transformer runs; a change is a run error, and none of that source's results are used. `completion.json` seals those digests as `reports_sha256`.
- A report file that later differs from its sealed digest is reported beside the run's verdicts, like a damaged attachment. It never rewrites them and never makes the store unreadable, because the tests, not the core, wrote it.
- `--run` is `--start`, then each selected validation's run command, then `--finish`, through the same code. It takes the run's lock before `start.json` exists, and `start.json` records `opened_by: run`, so no `--finish` ever picks the run up: not while it runs, and not after its process was killed, when its reports may be half written and its exit codes are lost. Such a run is closed with `--abandon`. There is one run kind, `validate`; a source says `command`, `exit_code` and `seconds` when the core ran it.

## Consequences

- Good: a run is complete by itself. Its folder holds the code stamp, the reports, the console captures and the verdicts, and an earlier run's reports stay exactly as they were.
- Good: no rule has to stop a report from deleting code, so the report-location guards are gone.
- Good: `--run` and `--start` + your tests + `--finish` store the same verdicts for the same tests, and the acceptance suite checks that they do.
- Good: no report is copied, so a large report costs no extra time or disk.
- Cost: a tool that always writes its report to a fixed place needs one setting pointing it at `{report}`. The Java fixture's `pom.xml` and the Kotlin fixture's `build.gradle.kts` each gained one build property.
- Cost: your own test step must take the path from `--start`'s output, so a CI script reads it rather than hard-coding it.
- Cost: reports now live inside `.use-cases/`, and the tests write there while a run is open. `.use-cases/` is no longer written by the core alone.

## Considered Options

- **Keep deleting, with stronger guards:** the path stays the project's choice, but a run still destroys files, and every new guard is one more rule to get right.
- **Move the old report aside instead of deleting it:** nothing is lost, but the project folder still fills with renamed reports, and the run is still not self-contained.
- **Copy the report into the run after the tests:** the run holds it, but the project path is still shared between runs, so an old report could be copied as new.

## Confirmation

These acceptance tests pin the rule:
- `test_every_run_keeps_its_own_reports_and_nothing_is_ever_deleted` (`test_helpers.py`)
- `test_run_is_start_then_the_commands_then_finish` (`test_helpers.py`)
- `test_a_new_run_never_reads_an_earlier_runs_report` (`test_swift_project.py`)
- `test_a_report_is_a_portable_name_never_a_path` and `test_a_validation_id_is_a_folder_name_on_every_system`
- `test_the_transformer_reads_the_report_where_the_tests_wrote_it_and_those_bytes_are_sealed`
- `test_a_report_that_changes_while_it_is_read_gives_no_results` and `test_a_report_changed_after_the_seal_is_a_warning_never_a_new_verdict`
- `test_tests_you_ran_yourself_between_start_and_finish`, in all nine fixture repos, with the path `--start` printed
- `test_a_run_in_progress_cannot_be_finished_by_anyone_else` and `test_a_crashed_run_leaves_no_evidence_and_blocks_nothing` (`--finish` never takes a run `--run` opened)

The core never removes or changes anything the tests wrote, or any sealed file. It removes only its own temporary files and scratch folders.

## Related Links

- `docs/design/12-results-storage.md` §2, §15, §20
- `docs/design/13-verify-flow.md` §2, §5–§7
- `docs/design/10-bridge-settings-and-transformers.md` §7, §8
- `docs/design/14-run-commands.md` §4
