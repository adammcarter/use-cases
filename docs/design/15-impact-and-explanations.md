# 15 — Impact + Explanations

**Phase:** 2 — Core Engine  
**Status:** Specification (locked)

## 1. Purpose

Status tells you *what* state a route is in. Explanations tell you *why*.

This chapter defines:

- why a route is stale: the run it changed since;
- why a route has no verdict: which rule withheld it;
- impact comparison between two route-state inventories;
- cache and recomputation rules that keep explanations correct.

Chapter 11 defines fingerprints and their components. Chapter 12 defines result lookup. Chapter 13 defines the guard that withholds verdicts.

V1 does not skip run commands automatically (section 12).

Examples in this chapter use a small Swift project. Nothing in the rules depends on it: the shapes are the same for any language and tool.

## 2. Two questions

```text
Impact:       did this route's declared inputs change?
Explanation:  why does this route have the status it has?
```

They are separate. An unchanged route may still be failed. A changed route may have returned to an older fingerprint with a matching pass and be verified again.

## 3. No Git dependency

The core has no branch, commit, diff, HEAD, or tracked-file model.

Impact compares resolved route states. A wrapper may obtain changed paths from Git, an editor, a watcher, or another source; those paths are hints (section 10) and never alter fingerprint semantics.

## 4. Stale explanations

A route is stale when history exists for it but no result matches its current fingerprint (chapter 12).

The store keeps whole fingerprints, not their components, so the core does not say which input changed. The explanation names the run the route changed since: the newest result for that use case and route.

```text
changed since run <id>
```

Example:

```text
shop.login.authenticate / unit-tests   stale
  changed since run 0000…2a  (last result: pass)
```

The core never invents a detailed cause. Impact comparison (section 7) names the components that differ when both inventories carry them.

Explanations identify affected inputs without copying source content or secrets into output.

## 5. No-verdict explanations

A route that received no verdict in its latest run has a manifest diagnostic (chapter 12). The explanation reports it with the run that produced it:

| Diagnostic | Meaning | What to do |
|---|---|---|
| its test didn't run | a validation link received no result | check the run command covers that test |
| code changed during the run | the route's inputs changed between the start point and the finish point; the diagnostic names the files | run again |
| not linked: no validation links and no procedure | the route has nothing a test report can reach | add markers or bindings, or verify with `use-cases record` |

Run errors (chapter 13) are explained at run level: which source failed and why.

## 6. Unlinked tests

Tests that transformers reported but that sit inside no link are listed as "test not tied to a use case", with file, line, and status. They affect no route. They show where coverage of the use-case matrix is missing.

## 7. Impact baseline

Impact analysis compares two explicit route-state inventories:

```text
baseline inventory
        |
compare by route identity
        |
current inventory
```

Each comparable entry contains:

```text
use_case
route
fingerprint
component fingerprints (when available)
```

An inventory also records which selection boundary it covers and whether it is complete.

A baseline may be a previously captured in-memory inventory, a retained inventory, or a caller-supplied compatible inventory. Its coverage and provenance must be explicit.

A run's result fingerprints may provide a partial baseline for routes represented in that run. They do not establish the whole workspace's previous route set. Absence from a partial baseline does not prove that a route is new.

## 8. Impact classifications

For comparable, complete inventories over the same boundary:

| Classification | Meaning |
|---|---|
| unchanged | Same route identity and equal compatible fingerprints. |
| changed | Same route identity and different comparable fingerprints. |
| added | Present now and absent from the complete baseline. |
| removed | Present in the complete baseline and absent now. |

When the baseline is missing, incomplete for that identity, or uses an incomparable fingerprint format, the classification is `unknown`.

`unknown` is an impact classification, not a route status.

## 9. Semantic impact

Chapter 11's fingerprint rules are authoritative.

| Change | Impact |
|---|---|
| Use-case intent changes | All that use case's routes change. |
| Implementation link content changes | All that use case's routes change. |
| Covered scenario changes | Routes covering that scenario change. |
| A route's validation link content changes | That route changes. |
| A route's resource content or membership changes | That route changes. |
| Route type, covers, gating, or procedure changes | That route changes. |
| Freshness policy changes | Every route changes. |
| Title, description, or out-of-scope changes | No route impact. |
| Bridge settings, run commands, or transformers change | No route impact. |
| Code moves without changing (`content` mode) | No route impact. |

Effects on other routes follow shared declared inputs, not inferred program dependencies.

## 10. Changed-path hints

A caller may supply changed paths to help the core find potentially affected inputs.

A path hint does not prove a route changed:

```text
file changed
    |
linked region unchanged
    |
route fingerprint unchanged
```

Likewise, absence from a hint list does not prove that a route's inputs are unchanged. The core may skip recomputation only when it can establish that cached inputs remain valid.

## 11. Discovery-sensitive inputs

Invalidation must account for changes to the set of discovered inputs:

- a new file matching a resource glob;
- a removed resource;
- a marker added to or removed from any file;
- a manual binding's file or range edited;
- a link transformer returning different links;
- a new child scope or changed definition file.

A reverse index containing only previously resolved files is insufficient to detect all of these. When its search space changes, a discovery-sensitive dependency must be reconsidered.

## 12. No automatic skipping in v1

`use-cases verify --run` runs every selected validation (chapter 13). It never skips a run command because the routes it touched last time are verified.

The manual subset is `--only <validation-id>` (chapter 14).

Automatic skipping would need to know, before running, which routes a run command's tests will reach. That is only known from the report afterwards, so v1 does not guess.

## 13. Conservative recomputation

When the core cannot prove which routes are unaffected, it recomputes the uncertain routes or all of them.

It must not produce false "unchanged" classifications or stale-looking verified statuses to preserve an optimization.

## 14. Fingerprint caches

Fingerprint and dependency caches are derived state. They may cache:

- normalized content hashes;
- link contributions;
- resource membership;
- component fingerprints;
- route fingerprints;
- reverse dependency mappings.

A cache must be invalidated or rebuilt when its inputs or governing policy may have changed.

File size and modification time alone are not sufficient proof of identical content.

Missing or invalid caches affect performance, not route semantics.

## 15. Workspace fingerprint limitation

The workspace fingerprint (chapter 11) is not a substitute for route fingerprints. It describes the authored model, not the content of linked files.

```text
same workspace fingerprint
```

does not prove:

```text
same validation inputs
```

## 16. Declared-input boundary

Explanations can only name inputs the core knows about: the use case, its links, and its resources.

Behaviour can also depend on undeclared inputs: toolchains, dependencies, environment, network services. A change there does not make a route stale. Declaring a file as a resource or binding brings it inside the boundary.

## 17. Final model

```text
current route states          baseline inventory
        \                            /
         \                          /
          compare component fingerprints
                     |
      unchanged / changed / added / removed / unknown
                     |
        impact: which components differ

stale route
        |
newest result for that use case and route
        |
explanation: changed since run <id>

latest run manifest
        |
no-verdict diagnostic
        |
explanation: which rule withheld the verdict
```
