# 12 — Results Storage

**Phase:** 2 — Core Engine  
**Status:** Specification (locked)

## 1. Purpose

Results storage persists validation evidence for a use case + route + fingerprint.

A **run** is the persistence container for one verify run (started by `use-cases verify --start` and finished by `use-cases verify --finish`, or started and finished by `use-cases verify --run`) or one `use-cases record` request. It holds the code as it was at the start point, the reports its tests wrote, the verdicts the core judged, and what went wrong along the way. Everything a verify run needs is inside its own folder.

Results belong to routes. Run identity, the validations that produced a result, group selection, and timestamps never enter the route fingerprint.

Only the core writes the store, with one exception: while a verify run is open, the tests write their reports into that run's `reports/` folder, at the paths the core gave them (section 15). Transformers never write under `.use-cases/`. A run never removes or changes anything its tests wrote, never changes a sealed file, and never touches another run's folder. The only files the core itself replaces are the run's manifest and log, once, before sealing (section 11), and its own temporary files. The one command that removes runs is `use-cases prune`, run by a person (section 31).

This chapter defines storage, durability, lookup ordering, recovery, and maintenance. Chapter 13 defines what a run does; chapter 07 defines how verdicts become status.

Examples in this chapter use a small Swift project. Nothing in the rules depends on it: the shapes are the same for any language and tool.

## 2. Workspace layout

All generated evidence belongs to the workspace root:

```text
.use-cases/
├─ run-order.json
└─ runs/
   └─ <run-id>/
      ├─ run.json
      ├─ start.json
      ├─ reports/
      │  └─ <validation-id>/
      │     └─ <report name>      (or the files the tests wrote here)
      ├─ outputs/
      │  └─ <validation-id>/
      │     └─ console.txt
      ├─ results.jsonl
      ├─ attachments/
      │  └─ sha256/
      │     └─ ab/
      │        └─ <remaining-digest>
      └─ completion.json
```

There is one root store. Child scopes write runs here regardless of where a request began.

Each run owns its manifest, start stamp, reports, console captures, result log, attachments, and completion marker. There is no workspace-wide result log and no shared attachment store. Indexes and temporary coordination files may also live under `.use-cases/`.

The generated directory is excluded from definition discovery, marker scanning, link resolution, and route fingerprints.

## 3. Generated state and Git independence

Deleting all generated history removes evidence without changing authored use cases, links, route definitions, DRAFT / READY state, or workspace validity. READY routes without retained history derive as unverified.

The core has no branch, commit, HEAD, worktree, tracked-file, or ignored-file model. Excluding `.use-cases/` from source control is recommended but is not enforced through Git.

## 4. Authority

The authoritative evidence is the collection of valid sealed run folders. Within each folder:

```text
run.json          what the run was and what happened
start.json        the code at the start point (verify runs)
reports/          the reports the run's tests wrote, as they were read
outputs/          console captures of the commands the core ran
results.jsonl     the verdicts the core judged
completion.json   the commit point
```

Indexes, summaries, caches, and databases are derived accelerators. Deleting them must not lose evidence.

`run-order.json` is allocation metadata, not validation evidence. Its only purpose is safe monotonic allocation of run IDs.

## 5. Run kinds

| `kind` | Request | What produces verdicts |
|---|---|---|
| `verify` | `use-cases verify --start`, then `use-cases verify --finish`; or `use-cases verify --run` | The reports the run's tests wrote into its `reports/` folder |
| `record` | `use-cases record` | A verdict a person or agent supplied |

`verify --run` is `--start`, the bridge's run commands, then `--finish` (chapter 13), so it makes the same kind of run. Its sources also say what ran: `command`, `exit_code` and `seconds`. The storage rules are the same for every kind.

## 6. Run lifecycle

```text
allocate run
    |
publish manifest + empty log
    |
create reports/<validation-id>/ for each selected validation (verify runs)
    |
write start.json (verify runs)
    |
tests run, yours or the core's run commands, writing into reports/
    |
read each report in place, transform, merge, judge (chapter 13)
    |
finalize manifest, append one result per judged route
    |
validate and atomically publish completion.json
    |
sealed immutable evidence
```

A folder without `completion.json` is active, started and waiting for `use-cases verify --finish`, or interrupted. It is inspectable for diagnostics but contributes no results to current freshness.

A valid `completion.json` seals the entire run. Its committed results become visible together. Sealed manifests, logs, reports, outputs, and attachments MUST NOT be edited or appended to.

A sealed run may contain pass, fail, incomplete, or error verdicts, or none at all. Sealing means evidence was committed; it does not mean validation passed or a human approved anything.

## 7. Result cardinality

A run holds at most one result per use case + route. Results from every validation in the run are merged before judging (chapter 13), so a route judged from several reports still has one result.

A route with no verdict in a run has no result record. The reason, such as "its test didn't run" or "code changed during the run", is a diagnostic in the manifest.

Validating again creates a new run. Retrying an uncertain storage commit is not a new run.

## 8. Run identity and ordering

V1 run IDs are 32 lowercase hexadecimal characters representing an unsigned 128-bit integer. The all-zero value is reserved. Fixed-width lexical order equals numeric order.

Every newly allocated run ID is:

```text
max(last + 1,  milliseconds since 1970 << 80  |  80 random bits)
```

- It is greater than every ID in the store, so IDs only go up locally, even if the clock goes back.
- Its top 48 bits are the time it was allocated, so runs from different machines sort by when they happened. A CI run and a developer's run of the same fingerprint are ordered by time once their stores are merged.
- Its 80 random bits make two stores that fork from one copy (CI shards restored from one cache, say) practically never allocate the same ID.
- The clock is only ever a tie-breaker between stores. Within one store, order is allocation order.

```text
latest applicable result
    = matching result from the greatest sealed run ID
```

There is no global result sequence and no per-result sequence field.

## 9. Allocation critical section

The core briefly takes an exclusive workspace allocation lock to:

1. Read and validate `run-order.json`.
2. Reconcile its high-water mark with existing run directory IDs.
3. Reserve a greater run ID.
4. Atomically persist and flush the new high-water mark before exposing the run.
5. Publish a fully initialized run directory and release the lock.

`run-order.json` contains exactly:

```json
{"order_version":1,"last_run_id":"0000000000000000000000000000002a"}
```

Gaps caused by crashes are valid. IDs are never reused: every ID is greater than every folder present when it was allocated, and its random part keeps deleted and forked histories apart.

A store without `run-order.json` (copied, or restored from backup) is valid: allocation continues above the greatest run folder present. Malformed or unsupported allocation metadata causes an allocation error, not a silent reset. An unsafe lock failure aborts allocation.

Only allocation uses this short shared critical section. Result appends, output copies, and attachment ingestion in different runs do not share a global lock.

## 10. Ordering concurrent runs

Ordering is by allocation, not completion time.

```text
run 2a starts
run 2b starts
run 2b seals: matching FAIL
run 2a seals later: matching PASS

current evidence remains run 2b's FAIL
```

An active newer run does not hide an older sealed result. When the newer run seals, its matching result takes precedence.

A later run for fingerprint B does not supersede an older matching result for fingerprint A when the current state is A. Matching occurs before ordering.

This rule prevents an older, slower run from replacing evidence produced by a newer request for the same fingerprint.

## 11. Run manifest

`run.json` is one UTF-8 JSON object without BOM, written in two steps by the run's owner:

```text
at allocation   identity + kind + planned sources (a started run stays like this until finished)
before sealing  the same object, finalized with what happened
```

The finalized manifest replaces the initial one atomically, once, before sealing. After sealing it is immutable.

Required fields:

```text
run_version = 1
run_id
created_at
kind                 verify | record
sources[]
errors[]
diagnostics[]
unlinked_tests[]
notes[]
```

`created_at` is UTC RFC 3339 diagnostic metadata. `run_id` must equal the enclosing directory name.

Each `sources` entry describes one validation from the bridge settings (chapter 10):

```text
id                   validation ID
report               where its report was written, relative to the run folder:
                     reports/<id>, or reports/<id>/<report name>
transformer          transformer name or path
working_dir          the folder its command runs in, when not the project root
command              the run command            (only when `verify --run` ran it)
exit_code            its exit code              (only with command)
seconds              its duration               (only with command)
diagnostics          what the transformer said about the report, for people
error                why this source produced no results
```

A `record` run has an empty `sources` list.

`errors` are run-level problems: a missing report, a report that changed while it was read, a transformer error, a build failure. They are never route verdicts.

`diagnostics` explain routes that received no verdict. Each names `use_case`, `route`, the `fingerprint` at the start point, and a `problem`:

```text
its test didn't run                                  + links: the links that got no result
code changed during the run                          + files: what changed since the start point
not linked: no validation links and no procedure
```

Link warnings found while resolving links (for example a marker for an unknown use case) are diagnostics with a `problem` only.

`unlinked_tests` lists tests the transformers reported that sit inside no link: `{test, file, line, status}`.

`notes` carry guidance, for example "aborted: closed by `use-cases verify --abort`" on a started run nobody finished.

Example:

```json
{
  "run_version": 1,
  "run_id": "0000000000000000000000000000002a",
  "created_at": "2026-09-25T12:34:00.000Z",
  "kind": "verify",
  "sources": [
    {
      "id": "auth-tests",
      "report": "reports/auth-tests/auth-tests.jsonl",
      "transformer": "swift-testing",
      "command": ["swift", "test", "--filter", "AuthTests", "--experimental-event-stream-output", "{report}", "--experimental-event-stream-version", "0"],
      "exit_code": 1,
      "seconds": 1.7
    }
  ],
  "errors": [],
  "diagnostics": [
    {"use_case": "shop.login.remember-me", "route": "unit-tests", "fingerprint": "uc-route-v1-sha256:89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567", "problem": "its test didn't run"}
  ],
  "unlinked_tests": [
    {"test": "AuthTests.LoginTests/notTiedToAnyUseCase()", "file": "Tests/AuthTests/LoginTests.swift", "line": 35, "status": "pass"}
  ],
  "notes": []
}
```

Publish the initial `run.json` and an empty `results.jsonl` together through a temporary directory and atomic rename, or an equivalent mechanism. Recognized unpublished temporary directories are not runs: a temporary directory under `runs/` is named `.tmp-` followed by anything.

### Start stamp

`start.json` records the code at the start point, for verify runs (chapter 13). It is written once, before any test runs, and never changes:

```text
start_version = 1
run_id
started_at             UTC RFC 3339, diagnostic only
opened_by            start | run: the request that opened the run; --finish finishes only runs --start opened
selected[]           the validations this run reads, after --only
validations_sha256   those validations exactly as use-cases-bridge.yml wrote them; --finish refuses if they changed
routes[]             { use_case, route, fingerprint } for every route
files                { <path>: <sha256> } for every linked and resource file
```

The finish point compares `routes` with the fingerprints it computes then; `files` lets a "code changed during the run" diagnostic name what moved. A record run has no start stamp.

```json
{
  "start_version": 1,
  "run_id": "0000000000000000000000000000002a",
  "started_at": "2026-09-25T12:33:58.000Z",
  "opened_by": "start",
  "selected": ["auth-tests"],
  "validations_sha256": "5b1c6bd5f6d4dcbf2ba3eb8f2f28c8c86a1b9c3e7e1f2a0cc2c5aa70e1c3d2f4",
  "routes": [
    {"use_case": "shop.login.authenticate", "route": "unit-tests", "fingerprint": "uc-route-v1-sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}
  ],
  "files": {
    "Sources/Auth/LoginService.swift": "8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4",
    "Tests/AuthTests/LoginTests.swift": "3b7e72edbd5ee4ee6d69d6fbd4c5e1d6a2a4a10aa4e0f2d5a5b8f8f58a9f1c1e"
  }
}
```

Several started runs may be open at once; `--finish` and `--abort` name the one they mean (chapter 13).

## 12. Result log format

Each run has its own UTF-8 JSON Lines `results.jsonl`:

- no BOM, comments, or blank lines;
- one JSON object per physical line;
- embedded newlines in strings escaped;
- core writers terminate every record with LF;
- compact deterministic serialization is recommended.

Physical append order carries no meaning.

Each record has these required fields:

```text
record_version = 1
use_case
route
fingerprint
status
links          { <link key>: pass | fail | error | incomplete | null }   (not on record results)
via            [validation IDs]  or  ["record"]
recorded_at
```

`links` shows every validation link of the route and the result it received; `null` means that link received none (only possible when another link failed, chapter 07). A `record` result has no `links` field.

`via` names the validations whose reports produced the verdict.

The storage locator for a verdict is run_id + use_case + route. Its applicability key is use_case + route + fingerprint.

A duplicate use case + route in one log is corruption, even if its fingerprint differs.

## 13. Result values

`status` is exactly one of:

| Stored value | Meaning |
|---|---|
| pass | Validation completed and expected behaviour was satisfied. |
| fail | Validation completed and expected behaviour was not satisfied. |
| incomplete | Validation did not reach a verdict, for example a skipped test. |
| error | The validation mechanism failed for this route. |

There is no skip result. A route that received no verdict has no record; its reason is a manifest diagnostic.

`fingerprint` records the route fingerprint at the start point (chapter 13); for a `record` result, when it was recorded (chapter 11). It must have a valid versioned representation. A syntactically valid historical format that the current core cannot compare remains history but cannot verify the current route; chapter 11's unsupported-format rule applies.

`recorded_at` is UTC RFC 3339 metadata. No timestamp controls ordering.

## 14. Optional result fields

```text
message        string
attachments    array of attachment descriptors
```

Diagnostics never alter freshness or override the recorded verdict. Process output belongs to `outputs/<validation-id>/console.txt`, not to results.

## 15. Reports and console captures

Every verify run owns its reports. At the start point the core creates one empty folder per selected validation:

```text
reports/<validation-id>/
```

and hands each validation one absolute path, `{report}` (chapter 10): that folder, or the report name the bridge settings give inside it. `verify --start` prints these paths; `verify --run` puts them into the run commands. The tests write their report there, and nowhere else is read.

So a run can never read a report from an earlier run, or from anything other than its own tests, and nothing is deleted to make that true. Earlier runs keep their reports untouched.

At the finish point the transformer reads the report in place. The core digests the validation's `reports/<validation-id>/` folder just before and just after the transformer runs. If anything changed, the source is a run error ("report changed while it was read") and none of its results are used. The digests taken when it was read are sealed in `completion.json` (section 20), so the sealed bytes are the bytes the verdicts came from.

The tests may keep writing after the finish point, for example a background process, or a script reusing an old path. A report file that later differs from its sealed digest is reported beside the run's verdicts, like a damaged attachment (section 17). It never rewrites them and never makes the run unreadable.

When `verify --run` runs a command, the core writes the command's bounded stdout/stderr capture (chapter 14) into:

```text
outputs/<validation-id>/console.txt
```

Only the core writes `outputs/`. Transformers and commands are never given a path inside it.

## 16. Run-local attachments

Attachments carry explicit supplementary evidence, typically supplied with `use-cases record` (a screenshot, a log excerpt).

```json
{
  "name": "checkout-failure.png",
  "blob": "uc-blob-v1-sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "size_bytes": 184233,
  "media_type": "image/png"
}
```

`name` is a nonempty display name, unique within that result, never a filesystem locator. `blob` identifies the SHA-256 digest of exact bytes, with no freshness normalization. `size_bytes` is a non-negative safe integer. `media_type` is an optional nonempty media-type string, taken from the file name's ending by one fixed table that is the same on every system; a file whose ending is not in it has none.

The descriptor resolves only inside the enclosing run:

```text
attachments/sha256/<first-two-digest-characters>/<remaining-62>
```

Same bytes may be deduplicated within a run. Separate runs own independent durable copies. Implementations may use copy-on-write storage when deletion or mutation in one run cannot affect another run's retained bytes.

No attachment lookup follows a display name, absolute path, traversal segment, or symlink outside the run.

## 17. Attachment ingestion and integrity

Ingest explicitly supplied evidence before appending its result:

```text
copy exact bytes to run-local temporary file
    -> hash and measure
    -> flush
    -> atomically publish digest path
    -> append descriptor with result
```

Once published, a blob is immutable. Ingestion failure prevents committing that result. Temporary or unreferenced blobs left by interrupted ingestion supply no evidence.

Missing or corrupt referenced blobs produce an integrity diagnostic. Because attachments are supplementary, such damage does not rewrite the historical verdict. Callers must be able to distinguish usable verdict data from damaged supporting evidence; the core must not present missing evidence as intact.

## 18. Per-run writes and locking

Writers within the same run serialize through a per-run exclusive storage lock or equivalent single-writer coordinator.

Inside that critical section, the core:

1. Verifies that the run is unsealed.
2. Recovers any permitted interrupted tail.
3. Reconciles an existing result for that use case + route under the idempotency rule below.
4. Validates and appends a complete result plus LF.
5. Flushes the required bytes before acknowledging staged persistence.

The run ID plus use case + route is the append idempotency key. Before the first append, the core prepares and retains the complete immutable candidate, including `recorded_at` and attachment descriptors. Reconciliation parses the existing record and compares all schema fields and values; JSON object member order is irrelevant and array order is significant.

If the same candidate already exists, return that staged result without another append. If a different candidate exists for the same key, return a conflict without changing the log. Do not regenerate timestamps when retrying an uncertain acknowledgment.

If the run has sealed meanwhile, reconciliation is read-only: validate the seal and return the identical committed result, or a conflict if the candidate differs or is absent.

The run lock is held by the process finishing, aborting or sealing the run, from the moment it chooses the run until the seal. A second process that wants the same run is refused; it never waits and never interleaves. Different runs are independent. Sealing checks for an existing `completion.json` before writing anything.

## 19. Staged persistence and commitment

Appending a result makes it durable staging within an active run. It is not yet freshness evidence.

Only sealing commits the run's results for lookup. Storage APIs must distinguish a staged candidate from a committed result and must not report verification success from staging alone.

## 20. Completion marker

`completion.json` is a UTF-8 JSON object containing exactly these required fields:

```text
completion_version = 1
run_id
finished_at
termination          completed | interrupted
result_count
manifest_sha256
results_sha256
outputs_sha256       { <path under outputs/>: <sha256> }
reports_sha256       { <path under reports/>: <sha256> }, a report as it was read
start_sha256         present exactly when the run has start.json
```

`manifest_sha256`, `results_sha256`, `start_sha256`, and each `outputs_sha256` and `reports_sha256` value are 64 lowercase hexadecimal SHA-256 digests of the exact persisted files. For a report the transformer read, the digest is taken as it was read (section 15). Any other file under `reports/` is digested at sealing. Both maps are empty for a record run. `result_count` equals the number of valid result records.

`termination` is never a route verdict. `interrupted` records that the request stopped before it completed: cancelled, or a started run closed by `verify --abort`. An interrupted run's manifest says which sources were not processed; it never invents verdicts for them.

## 21. Sealing transaction

With exclusive per-run coordination and no remaining writers:

1. Validate the finalized manifest and every result.
2. Validate referenced attachment integrity and every output file.
3. Flush manifest, log, outputs, and attachments to the required durability boundary. Reports were written by the tests; the core does not rewrite them.
4. Compute the digests.
5. Write and flush a temporary completion marker.
6. Atomically publish `completion.json` without overwriting an existing marker.
7. Flush the directory as required before reporting commitment.

A valid marker is the commit point. After it is published, no run data may change.

If completion already exists after an uncertain response, validate it and return the existing commitment when it matches. Do not append duplicate evidence or silently replace a different completion.

## 22. Reads and visibility

A query establishes a consistent view of sealed runs. A run sealed after that view begins may appear on the next query.

Readers validate completion metadata, manifest identity, digests, counts, and result schemas before using a sealed run. A report that no longer matches `reports_sha256` is the one exception: the tests wrote it, so the reader reports the change beside the run's verdicts and still uses them (section 15). Derived indexes may cache this work only when they can establish their cached data still corresponds to authoritative files.

Unsealed folders are reported separately as pending, started, or interrupted work and do not contribute to route history. `status` lists each run that never finished as a workspace warning, `run <id> never finished`; it is never evidence. Anything under `runs/` that is not a run ID folder and not a recognized temporary directory (a stray folder, or a stray file such as one a file browser leaves) is a storage error naming it; nothing there is skipped silently.

After sealing returns success, subsequent queries must see the run. A stale index must refresh or fall back. Readers must not mix half-published evidence with committed results.

## 23. Crash recovery

Recovery is local to an unsealed run. It must first establish that the original owner is no longer active; absence of a recent timestamp alone is insufficient.

A valid complete final record without LF may be retained, then repaired by adding LF under the run lock.

A syntactically incomplete final JSON fragment without LF is an interrupted append: ignore it for inspection, report a warning, and remove only that tail before further storage work.

A complete JSON value with invalid fields, an unsupported version, a malformed LF-terminated line, a duplicate use case + route, or mid-file damage is corruption. Do not disguise it as an interrupted append.

Recovery may seal the intact results with termination `interrupted`. It does not rerun commands, rerun transformers, or fabricate verdicts. A fresh request uses a new run.

Sealed runs are never tail-repaired. Any inconsistency with a published completion marker is corruption.

## 24. Storage errors

A corrupt or unsupported sealed run must not be silently skipped as though it never existed. Status queries whose history cannot be established report a result-storage error. A conservative full-store query may fail rather than infer unaffected routes from damaged metadata.

An invalid published completion marker is corruption, not an unsealed run. A run with a valid marker but missing required files is also corrupt.

A storage error is not the route status `error`. The latter records a validation-mechanism failure for a known fingerprint.

If sealing fails before the commit point, staged verdicts remain unavailable to freshness. If commitment may have occurred but acknowledgment failed, report uncertainty and reconcile the marker; do not claim no durable result exists without checking.

## 25. Strict schemas and versions

Run, result, completion, and allocation schemas have separate versions, independent of authored `schema_version`, the bridge contract version, and the fingerprint version.

Every version keeps one envelope, forever, with the same meaning:

```text
completion.json   run_id, result_count, manifest_sha256, results_sha256
run.json          run_id
each result       use_case, route, fingerprint, status
```

A reader checks the envelope's digests for every sealed run. For a version it supports, it reads the rest and ignores fields it does not know. For a newer version, it reads the envelope only: the result still counts for status, and everything else is left alone. So a store written by a newer core stays readable by every older one, and evidence never has to be migrated. A future version that cannot keep the envelope is a new store, not a new run version.

Writers write exactly their version's schema. Manual editing of manifests, logs, outputs, markers, and allocator metadata is unsupported.

## 26. Missing history

A missing runs directory or an empty collection of sealed runs means empty applicable history. It is valid.

Active or interrupted unsealed folders do not themselves make a route stale. If no sealed history exists for a READY route, it derives as unverified, with each run that never finished reported separately as a workspace warning (section 22).

## 27. Applicability and freshness

For current use case U, route R, and fingerprint F:

```text
history  = committed results from valid sealed runs for U + R
matching = history with a compatible fingerprint equal to F

if matching exists:
    choose the result with greatest run_id
    pass       -> verified
    fail       -> failed
    incomplete -> incomplete
    error      -> error
else if history exists:
    stale
else:
    unverified
```

Gating and aggregate worst-status rules are those of chapter 07.

When a route has no matching result, the most recent manifest diagnostic for U + R + F explains why (for example "its test didn't run"). Diagnostics explain; they never count as results.

Results for different fingerprints remain historical evidence. Restoring an exact old state can reuse its greatest-ID matching result. Results do not expire by age.

## 28. Identity guarantees

Deleted routes leave inert history. A route rename changes identity and does not transfer evidence automatically. Restoring the same route identity and fingerprint can restore applicability.

Groups, validation IDs, and run kinds never change applicability. Provenance never substitutes for the use case + route + fingerprint match.

A result's fingerprint describes the code its verdict was judged against. Chapter 13's guard withholds a verdict whenever that cannot be established: "code changed during the run", for both kinds of verify run.

## 29. Derived indexes

An index may map:

```text
use_case
use_case + route
use_case + route + fingerprint
    -> run_id + record location
```

Indexes discover new seals, detect missing or changed folders, and rebuild from authoritative run files when stale, incompatible, corrupt, or uncertain.

An index update failure after sealing does not undo the commitment. The next read refreshes or falls back. No index can be the only record that a run or verdict exists.

Efficient implementations avoid rescanning every run for every route query, reuse validated immutable run metadata, and incrementally index newly sealed runs.

## 30. Retention and deletion

Nothing is deleted automatically: no age limit, no count limit, no eviction under disk pressure. Every verify and record run adds a folder, and the store grows until a person prunes it. `status` shows how big it is (chapter 16 §9).

The only deletion is `use-cases prune` (chapter 16 §20), a command a person runs. No run, no other command and no agent tool removes a run (chapter 20). Prune removes whole run folders and every file each one owns: its manifest, start stamp, reports, outputs, log, attachments and completion marker. It never removes, adds or rewrites a file inside a run it keeps (a lock file it made to take a run's lock is taken away again), and never lowers the allocator high-water mark.

Prune excludes active writers and coordinates with readers. It takes each run's lock (section 18) before touching it, and leaves a run another process holds. Under the lock it moves the run's folder out of the runs namespace in one rename, to a temporary name readers pass over (section 22), `runs/.tmp-prune-<run-id>`, and only then deletes its bytes. A reader that listed the run before it left treats it as absent, never as damaged or unfinished, so a reader sees the whole run or none of it. A run another prune removed first is passed over without a word.

## 31. Pruning superseded runs

`use-cases prune` removes the sealed runs whose every part a later sealed run has said again and that `status` does not use for the workspace as it is now. It loads the workspace and fingerprints its routes as `status` does (chapter 11). A sealed run is **superseded** when all of these hold:

- a later sealed run exists;
- `status` does not read it for any route at the route's current fingerprint: it holds neither the result that decides the route (section 27), nor the diagnostic that explains why the route has none, nor the newest result the route has changed since;
- every result in it has a result in a later sealed run for the same use case + route, at any fingerprint;
- every diagnostic in it that names a use case + route has a result or a diagnostic in a later sealed run for the same use case + route.

A run with no results and no such diagnostics is therefore superseded by any later sealed run. The newest sealed run is never superseded, so a store that has sealed runs keeps at least one.

Prune never touches:

- any run, when the workspace is INVALID: what `status` uses cannot be known, so prune refuses as `status` does and deletes nothing;
- a run with no completion marker: started and waiting for `--finish`, or interrupted (section 6);
- a run whose lock another process holds;
- a corrupt or unreadable run. A store that cannot be read safely is not pruned at all: prune refuses with a storage error, as `status` does (section 24);
- a run whose manifest is of a version this core does not read (section 25): what it explains is unknown, so it is kept.

The superseded set is worked out together, from one read of the store, so a run that supersedes another is never itself in the set.

A prune stopped between the rename and the delete leaves its `runs/.tmp-prune-<run-id>` folder behind: no run any more, and passed over by readers. Every prune removes such leftovers it finds, whatever they hold, since they are its own, and lists each one as a leftover it removed.

**What it keeps.** For the workspace as it is now, prune changes no answer of `status` or the gate: no status, no summary count, no gate answer and no route note. Every route keeps the result that decides it at its current fingerprint (the greatest run ID at that fingerprint, section 27), the newest result it has changed since, and the newest diagnostic that explains it, wherever the code is: code put back to an older state keeps the older run that decides it. The only differences in `status --json` and the gate's document are run IDs and paths, the store's own size and run count (chapter 16 §9), and the workspace warnings about integrity findings in the removed runs themselves: their files are gone.

**What it loses.** Audit history: the older verdicts and reasons a later run said again. And the verdicts for older code states the code later returns to: a result at fingerprint F that no route is at when prune runs, superseded by a later result for the same route at F′, is gone, so when the code later returns exactly to F the route reads `stale` instead of reusing the old verdict. The tests run again prove it afresh.

There is no workspace-wide log to compact, and prune never rewrites a sealed log to remove individual records. Orphan blobs inside a run may be removed only during explicit recovery with the run's lock held; the run's validated log is the reference authority, never an index.

## 32. Copying and portability

Evidence is not bound to an absolute workspace path or machine identity. Copying a complete valid sealed run can provide applicable evidence in another workspace with matching identities and fingerprints.

Copying preserves run IDs and file bytes, so merging stores is copying their run folders into one `runs/`. Run IDs from different stores do not collide in practice (section 8), and the newest matching result wins by time. A same-ID folder that differs is a conflict: keep one, never merge the two.

Trusting copied evidence belongs to the caller.

## 33. Privacy and trust boundary

V1 evidence is locally trusted data. Hashes and sealing detect storage inconsistency; they do not prove who ran the tests, whether a report was honestly produced, or whether someone rewrote all hashes.

No cryptographic signatures, authentication, machine attestation, or remote store is required. Runtime data is not encrypted by the core.

Reports and console captures may contain anything a test tool prints. The core should avoid unnecessary secrets in messages and attachments, and users should keep secrets out of test output. Hostname, username, device ID, absolute workspace path, and inherited environment are not persisted as applicability inputs.

## 34. Example result

The following object occupies one compact physical line in its run's log:

```json
{
  "record_version": 1,
  "use_case": "shop.login.authenticate",
  "route": "unit-tests",
  "fingerprint": "uc-route-v1-sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "status": "pass",
  "links": {
    "shop.login.authenticate#unit-tests.valid-credentials@Tests/AuthTests/LoginTests.swift:6": "pass",
    "shop.login.authenticate#unit-tests.invalid-password@Tests/AuthTests/LoginTests.swift:13": "pass"
  },
  "via": ["auth-tests"],
  "recorded_at": "2026-09-25T12:34:56.123Z"
}
```

Its run ID comes from its folder and manifest. There is no global sequence to assign.

## 35. Reference write algorithm

```text
allocate run ID under short allocation lock
publish initial manifest and empty per-run log
create reports/<validation-id>/ for each selected validation
--run: take the run lock, held until the seal
write start.json (opened_by: start or run)
    --start: return each validation's {report} path; your tests write there; `--finish` continues below
    --run: run each command with its {report}, capturing its console
for each validation source (chapter 13):
    digest its reports/<validation-id>/, call the transformer's results job on the report in place, digest again
    changed while read: a run error, no results from this source
merge results from every source
judge every route (chapter 07) and apply chapter 13's guard
ingest attachments (record)
append one result per judged route under this run's lock
finalize manifest (sources, errors, diagnostics, unlinked tests, notes)
seal run through atomic completion marker
refresh derived index or mark it stale
return committed run and results
```

## 36. Reference read algorithm

```text
establish consistent runs view
discover sealed folders and diagnose pending folders
validate or reuse a provably current index
validate required authoritative evidence
find history for use_case + route
filter by compatible current fingerprint
choose greatest matching run ID
derive route state
aggregate gating route states using chapter 07
```

## 37. Performance and correctness

The normal write path uses one short allocation lock, run-local appends, and one sealing transaction. No full history rewrite is required.

The lookup path should use a derived route/fingerprint index. Attachment deduplication is local to each run. Pruning operates on whole folders (section 31).

Optimizations must preserve coherent commitment, deterministic run ordering, exact fingerprint applicability, corruption detection, report, output and attachment ownership, and visibility after successful sealing.

JSON and JSONL remain ordinary inspectable filesystem formats. No database is required; a database may serve as a disposable index.

## 38. Final model

```text
reports + recorded verdicts
        |
core judges (chapter 07, chapter 13)
        |
active run folder
        |
atomic seal
        |
immutable run history
        |
use case + route + fingerprint
        |
greatest matching run ID
        |
derived runtime state
```

Run folders own durable evidence. Fingerprints determine applicability. Run IDs determine precedence. Indexes provide speed.
