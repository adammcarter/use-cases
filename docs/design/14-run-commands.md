# 14 — Run Commands

**Phase:** 2 — Core Engine  
**Status:** Specification (locked)

## 1. Purpose

A run command is what `use-cases verify --run` starts. It is extension point 3 (chapter 10): settings only, no code to write. It can be any command in any language; for example, in a Swift project:

```yaml
validations:
  - id: auth-tests
    report: auth-tests.jsonl
    run: [swift, test, --experimental-event-stream-output, "{report}", --experimental-event-stream-version, "0"]
    transformer: swift-testing
    timeout_seconds: 900
```

This chapter defines how the core launches, supervises, and captures a run command. Chapter 13 defines where run commands sit in the verify flow: `--run` is `--start`, these commands, then `--finish`.

A run command's exit code never decides a route verdict by itself. Verdicts come from the transformer's per-link results and the core's judging rules (chapter 07). The exit code is used only to detect a build failure (section 13) and is passed to the transformer.

## 2. Selection and order

```text
use-cases verify --run                      every validation; one without a run command is a run error
use-cases verify --run --only auth-tests    only the named validations
```

- `--only` takes one or more validation IDs. An unknown ID refuses the request before anything runs.
- Selected commands run sequentially, in the order they appear in `use-cases-bridge.yml`.
- V1 has no parallel execution of run commands. Test tools commonly share build directories, and sequential order keeps the project state predictable.

## 3. One command covers many routes

A single run command normally exercises many routes at once:

```text
test command ──▶ one report ──▶ transformer ──▶ results for every link the tests sit in
```

There is no per-route command. The number of launches equals the number of selected validations, not the number of routes.

## 4. Where the report goes

Each run has its own reports folder, created at the start point (chapter 12): `.use-cases/runs/<run-id>/reports/<validation-id>/`. The command writes its report there, through `{report}`.

```text
start point     creates runs/<run-id>/reports/<validation-id>/, empty
launch command  with {report} = that folder, or the report name inside it
```

A command that fails to write a report therefore can never be credited with an earlier run's results: an earlier run's report is in that run's folder, never in this one. Nothing is deleted before, during or after a command; the source reports "no report".

## 5. `{report}` substitution

The core replaces every occurrence of the placeholder `{report}` in `run` with the absolute path of the validation's report in this run (chapter 10): its reports folder, or the report name inside it. The folder already exists. No other substitution happens: braces that are not the placeholder (chapter 10 §8), such as a word in braces like `'{print}'`, a shell brace group or `${HOME}`, reach the command as written. A mistyped placeholder, a near miss of `report` such as `{reprot}`, never gets this far: the bridge file is INVALID and names it.

A tool that writes its report to a fixed place needs one setting that points it at `{report}`, for example a build property the command sets:

```yaml
run: [mvn, -q, -B, test, "-DjunitDir={report}"]      # the build reads junitDir as the report folder
```

## 6. Direct process execution

The core launches one direct process. It does not invoke an implicit shell.

```text
exec(run[0], run[1..])
```

not:

```text
sh -c "..."
```

Shell syntax has no special meaning unless a shell is explicitly the executable:

```yaml
run: [bash, scripts/test-all.sh, "{report}"]
```

## 7. Executable resolution

```text
bare name        swift, pytest, node     -> resolved through the process PATH
relative path    scripts/test-all.sh     -> resolved from the command's working folder (section 8)
absolute path    /opt/tools/runner       -> allowed, with a portability warning
```

On Windows a bare name is found as the Windows shell finds it, through `PATH` and `PATHEXT`, so `mvn` finds `mvn.cmd`; a `.cmd` or `.bat` runs through `cmd.exe`. The same `run` setting then works on every operating system, as long as the tool itself is installed.

A command that cannot be resolved or launched is a run error: "command could not be launched: <reason>".

## 8. Working directory and environment

- The working directory is the validation's `working_dir`, or the workspace root when it has none (chapter 10). In a repository of several projects, each validation runs in its own project folder, with no `cd` wrapper.
- The environment is the Use Cases process environment, inherited unchanged.
- V1 has no per-command environment overlay. A command needing one uses a wrapper script.
- `{report}` is always an absolute path, so it is the same wherever the command runs.

## 9. Standard input and terminal

- stdin is closed (EOF). Commands receive no interactive input.
- No pseudo-terminal is allocated. Commands must not depend on TTY behaviour.

## 10. Output capture

The core captures stdout and stderr together, in the order the command wrote them, into one console capture. The capture is drained as the command runs, so the command never blocks on a full pipe.

At most 1 MiB is retained. For a larger capture the core retains the first 512 KiB, a marker saying how many bytes were not kept, and the last 512 KiB.

Retained output is decoded as UTF-8; invalid sequences become U+FFFD.

The capture is stored as `outputs/<validation-id>/console.txt` in the run (chapter 12). The core never parses console output to decide anything.

## 11. Timeout

`timeout_seconds` is optional. When omitted, the core default of 600 seconds applies.

- Timing uses a monotonic clock and begins after successful launch.
- Each command runs in its own process group. On timeout the core asks the whole group to terminate, waits up to 2 seconds, then forces it, so background children of the command stop too.
- A timeout is a run error: "command timed out after N seconds". No route gets a verdict from that source, even if a partial report exists.

## 12. Normal and abnormal termination

```text
normal exit, report present     -> transformer reads the report (chapter 13)
normal exit, no report          -> run error "no report: nothing was written to reports/<id>..."
killed by a signal              -> run error "command terminated abnormally (signal N)"
```

## 13. Build failures

A test tool that fails to build usually exits non-zero without running any test.

```text
exit code != 0   and   the transformer returned no fail or error result
    -> run error "command exited N without any failing test (build failure?)"
    -> no route gets a verdict from this source
```

An exit code of 0 with a report whose tests failed is still judged from the report: the report is the evidence.

## 14. Cancellation

On cancellation the core stops starting new commands and terminates the active one as in section 11. The run is sealed as interrupted (chapter 13).

## 15. No automatic retry

One request launches each selected command once. The core does not retry failures, errors, or timeouts. Running again is a new request and a new run.

## 16. Security

V1 provides no sandbox.

Run commands execute with the operating-system permissions of the Use Cases process. They may access the network, absolute paths, databases, and system APIs. Such external state is outside route fingerprints (chapter 11).

Run commands and transformers are trusted in the same way the project's own test commands are trusted. Review `use-cases-bridge.yml` as you would a build script.

## 17. Final model

```text
use-cases verify --run [--only ids]
        |
for each selected validation, in file order:
        |
   {report} = this run's reports/<id>/ folder, or the name inside it
        |
   exec run (no shell, its working folder, inherited env, no stdin, own process group, timeout)
        |
   capture console (bounded) ──────────▶ outputs/<id>/console.txt
        |
   the finish point (chapter 13), shared with --finish:
        |
   report present? ── no ──▶ run error
        |
       yes
        |
   transformer results job, report read in place (chapter 10)
        |
   non-zero exit and nothing failed? ── yes ──▶ run error (build failure)
        |
       no
        |
   results into the merge (chapter 13)
```
