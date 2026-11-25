# 04 — Workspace Structure

This document defines how Use Cases discovers scopes and authored definitions across a repository.

## Core model

```text
workspace root
   |
   +-- use-cases.yml
   |
   +-- 0..N child scopes
          |
          +-- use-cases.yml
```

Use Cases cares only about filesystem hierarchy and its own YAML files.

It has no concept of Git repositories, packages, modules, languages, build systems, or package managers.

## Workspace root

The workspace root is the directory containing the top-level:

```text
use-cases.yml
```

Exactly one root scope is required.

All repository-wide paths are anchored to this root.

## Recommended layout

```text
repo/
├─ use-cases.yml
├─ sources/
├─ tests/
├─ use-cases/
├─ use-case-groups.yml
├─ use-cases-bridge.yml     (optional helpers)
└─ .use-cases/
   └─ runs/
      └─ <run-id>/
```

Recommended separation:

```text
use-cases/            behavioural contracts
sources/              implementation
tests/                validation code
use-cases-bridge.yml  optional helpers: transformers and run commands
.use-cases/           generated runtime state and immutable per-run evidence
```

Other layouts remain valid.

## Filesystem vs semantics

```text
Filesystem = organisation
YAML       = semantics
```

Directory names and filenames never create namespace segments.

Moving a definition file within its scope's `use_cases_dir` does not change its identity. Moving it into another scope does, because scope prefixes compose.

## The workspace root

The root `use-cases.yml` says so:

```yaml
schema_version: 1
root: true
prefix: shop
```

- Exactly one `use-cases.yml` in a workspace says `root: true`: the root's. IDs are composed from there, so they are the same whichever folder a tool is started in.
- Pointing the core at a folder whose `use-cases.yml` lacks `root: true` is refused: it is a child scope, and its IDs would come out different.
- A folder below the root whose `use-cases.yml` says `root: true` is a separate workspace, such as a vendored package or a submodule with its own use cases. The parent never enters it; its use cases, markers and store stay its own.

## Scope

A scope is a directory containing:

```text
use-cases.yml
```

Scopes may appear anywhere beneath the workspace root.

```text
repo/
├─ use-cases.yml
└─ packages/
   └─ auth/
      ├─ use-cases.yml
      └─ ...
```

The physical depth of a scope has no semantic meaning.

## Parent / child relationship

A scope's parent is its nearest ancestor directory containing `use-cases.yml`.

```text
root
 |
 auth
 |
 oauth
```

No explicit include graph exists.

Child scopes are discovered automatically.

## Schema version

Every scope must explicitly declare:

```yaml
schema_version: 1
```

Schema version is never inherited.

All scopes in one workspace must use the same schema version.

```text
missing version  -> INVALID
version mismatch -> INVALID workspace
```

Use Cases never combines scopes with mismatching schema versions.

## Scope prefix

A scope may declare an optional namespace prefix:

```yaml
prefix: auth
```

Prefixes compose explicitly:

```text
root prefix   app
               +
child prefix  auth
               +
file prefix   login
               +
local id      success
               |
               v
app.auth.login.success
```

If a child scope omits `prefix`, the parent namespace passes through unchanged.

```text
child prefix present -> append it
child prefix absent  -> inherit resolved namespace unchanged
```

No prefix is ever inferred from directory names.

## Definition-file prefix

A discovered use-case definition file may also declare an optional prefix.

```yaml
prefix: login

use_cases:
  - id: success
```

Resolved identity:

```text
resolved scope namespace
+
optional file prefix
+
local use-case id
```

The file's physical path does not affect this identity.

## Recommended file structure

Inside a `use_cases_dir`, the recommended structure is one file per group, at the path its prefix spells:

```text
use-cases/
├─ login.yml            prefix: login           shop.login.success, shop.login.lockout
├─ refunds.yml          prefix: refunds         shop.refunds.partial
└─ payments/
   ├─ card.yml          prefix: payments.card   shop.payments.card.refund
   └─ wallet.yml        prefix: payments.wallet
```

- Each file holds one group: every use case in it shares the file's prefix.
- The file's path follows its prefix: each segment but the last is a folder, the last is the file name.
- Files stay small and easy to find, for people and tools alike.

This is a recommendation, not a rule of identity: identity still comes from the YAML alone, and any other layout is valid. Commands that write use cases follow it (chapter 16 §14): they add to the file that already holds the group, and create a new file only when no file does, at the path this structure gives.

## `use_cases_dir`

Each scope may declare:

```yaml
use_cases_dir: use-cases
```

If omitted:

```text
use_cases_dir = use-cases
```

`use_cases_dir` is relative to that scope's directory.

It may not escape the scope directory.

```text
use_cases_dir: use-cases   valid
use_cases_dir: ../shared   invalid
```

## Definition discovery

Supported definition files:

```text
*.yml
*.yaml
```

The ending is spelt in lower case. A file in a `use_cases_dir` ending `.YML`, `.Yaml` or any other casing of them is INVALID, and the message names the lower-case spelling to rename it to: it is never read as a definition and never skipped.

Files are discovered recursively inside the scope's `use_cases_dir`.

A `use_cases_dir` that does not exist is read as an empty one: the scope has no use cases. Git never stores an empty folder, so a missing folder and an empty one must give the same answer on every checkout. `validate` still shows the count, so a misspelt folder reads `0 use cases`.

The scope's own `use-cases.yml` is configuration, not a definition file.

No explicit include graph is required.

## Scope ownership

A definition belongs to the scope whose `use_cases_dir` holds it.

```text
root scope
   |
   +-- use-cases/        root definitions
   |
   +-- payments/         child scope, beside use-cases/, never inside it
          |
          +-- use-cases/ child definitions
```

A child scope never sits inside another scope's `use_cases_dir` (below), so no definition is loaded twice.

A child scope may not sit inside another scope's `use_cases_dir`: that folder belongs to one scope, and a scope inside it would leave some files owned by neither. It is INVALID. A scope's `use_cases_dir` also may not contain that scope's own `use-cases.yml`, and every YAML file inside it must be a use case definition.

## Cross-scope links

A use case may link to implementation or validation content anywhere inside the workspace, through markers or manual bindings.

```text
root use case  ------> child code
child use case ------> shared/root code
```

Scope ownership affects authored definitions, not where links may point.

## Path coordinate system

All link, resource and runtime paths are repository-root-relative, and always use `/` as the separator, on every operating system.

This includes:

- manual binding file paths
- validation resource file paths
- validation resource globs
- `working_dir` folders in `use-cases-bridge.yml`

A run command runs in its validation's `working_dir`, a repository-root-relative folder, or at the root when it has none (chapter 14).

Paths are never relative to:

- current working directory
- use-case definition file
- child scope directory

`use_cases_dir` is the exception: it is scope-relative because it defines authored-definition ownership.

## Runtime state

There is one generated runtime directory at workspace root:

```text
.use-cases/
```

Child scopes do not have their own `.use-cases/`.

`.use-cases/` contains generated outputs only.

It never contains authored definitions or configuration.

Its verification evidence is organised as one folder per run:

```text
.use-cases/
├─ run-order.json
└─ runs/
   └─ <run-id>/
      ├─ run.json
      ├─ start.json
      ├─ reports/
      │  └─ <validation-id>/      the tests write their report here
      ├─ outputs/
      │  └─ <validation-id>/
      │     └─ console.txt
      ├─ results.jsonl
      └─ completion.json
```

Only the core writes here, with one exception: while a verify run is open, the tests write their reports into its `reports/` folder, at the `{report}` paths the core gives them. Each run keeps everything it was judged from, and no run ever deletes or touches another's folder.

The exact run contents, sealing, and retention rules belong to `12 — Results Storage`. The workspace-structure rule is only that all run folders live under this one root runtime directory.

## Bridge settings

Helpers are configured in one optional file at the workspace root:

```text
use-cases-bridge.yml
```

Rules:

- optional: a workspace without it is valid, and the core works alone
- root only in v1: child scopes never have their own
- configuration only: it never contains use cases or results
- `working_dir` folders it names are workspace-root-relative and may never point inside `.use-cases/`
- it never says where reports live: each run owns its reports, and a validation names at most the report's file or folder name

Its contents are defined in `10 — Bridge settings + transformer contract`.

## Status boundary

Status may be read for any scope.

```text
status of root
   -> root + all descendant scopes

status of child
   -> child + all descendant scopes
```

Every run, whatever it covers, lives beneath the single root `.use-cases/` directory.

## Empty scopes

A scope may contain zero use cases.

```text
valid + WARNING
```

## Discovery exclusions

By default, Use Cases excludes its own generated state and version-control history, at any depth (ADR 012):

```text
**/.use-cases/**   **/.git/**   **/.hg/**   **/.svn/**   **/.bzr/**   **/.jj/**
```

These hold a history or copy of the workspace, not the workspace itself; a commit message that mentions a marker must never make a repository INVALID.

The root config may add filesystem traversal exclusions:

```yaml
discovery:
  exclude:
    - generated/**
    - vendor/copied/**
```

Exclusions are relative to workspace root.

Excluded trees are not searched for:

- use-case definitions
- child scopes
- markers

The core has no built-in list of build, test or dependency folders: beyond the defaults above, nothing is skipped unless the workspace excludes it. A root config usually excludes its build and dependency folders, for example:

```yaml
discovery:
  exclude:
    - "build/**"
    - "**/node_modules/**"
```

Patterns use the path pattern dialect below. As in `.gitignore`, a pattern that matches a folder excludes the folder and everything in it, and the folder is never entered: `vendor`, `vendor/**` and `**/vendor` all exclude a top-level `vendor/`.

Exclusions hide folders from everything the core searches: scopes, definitions, markers, resource globs and links transformers. A path the workspace names explicitly, such as a manual binding or a file resource, may point into an excluded folder.

## Path spelling

A path the workspace names (a manual binding, a resource, a `working_dir`, a transformer program) must match the on-disk spelling exactly: case and Unicode form included, on every operating system. `Src/app.js` does not name `src/app.js`, even on a Mac. A mismatch is INVALID and the message names the on-disk spelling.

## Path patterns

Every authored path pattern (resource globs, `discovery.exclude`) uses one dialect:

```text
*    any characters within one path segment        *.json, test_*
?    exactly one character (one Unicode code point) within a segment
**   zero or more whole segments                   schemas/**/*.json, build/**, **/node_modules/**
```

- Everything else is literal. There are no character classes or braces.
- `**` must be a whole segment: `a**` is INVALID.
- Patterns are workspace-relative with `/` separators; `/x`, `./x`, `a//b`, `a/`, `..` and `\` are INVALID (chapter 09 §19).
- Matching is case-sensitive and uses the on-disk spelling.
- `**` is zero or more segments wherever it stands, so `build/**` matches `build` itself as well as everything inside it, and `**/*.json` matches `a.json` at the root.

## Symlinks

The core never follows a symlink, to a file or a folder. A symlink is an entry whose content is its target text, with `/` separators: exactly what git stores, and what a Windows checkout without symlink support writes into a plain file. So the same commit fingerprints the same on every system. A marker can't live behind a symlink, and a binding to one tracks its target text, wherever it points, not what is there.

## Symlink discovery

Directory symlinks are not followed during scope/definition discovery in v1.

## Git and repository tooling

Use Cases has no Git model.

Nested Git repositories, submodules, package boundaries, or other repository tooling do not alter discovery semantics.

```text
directory contains use-cases.yml
        |
        v
scope
```

## Root-only policy

Repository-wide policy belongs only in root `use-cases.yml`.

Example:

```yaml
root: true

freshness:
  binding_identity: content
  normalization:
    ignore: []

discovery:
  exclude:
    - generated/**

sign_off: required
```

Child scopes inherit repo-wide policy and cannot override root-only settings. A child scope that sets `sign_off` is INVALID.

`sign_off: required` turns on the sign-off gate (chapter 16 §10, chapter 21): a use case whose promise is not approved as it reads now is held. Without it, approvals are still recorded and shown, and never gate.

## Freshness policy

Root config may define:

```yaml
freshness:
  binding_identity: content
```

Allowed:

```text
content
content-and-locator
```

If omitted:

```text
content
```

Meaning:

```text
content
  -> same bound content remains fresh even if locator moves

content-and-locator
  -> locator movement also makes previous verification stale
```

By default, line endings are ignored when content is compared, so an LF and a CRLF checkout of the same commit agree (chapter 11 §12). If `freshness.normalization` or its `ignore` is omitted, it is equivalent to:

```yaml
freshness:
  normalization:
    ignore: [line-endings]
```

`ignore: []`, written out, means exact comparison.

Optional language-agnostic normalization may ignore:

```text
line-endings
whitespace
```

No generic comment normalization exists because Use Cases does not understand programming languages.

## Configuration inheritance

For future settings explicitly designed as overridable:

```text
nearest explicit scope value
        |
        v
parent value
        |
        v
core default
```

Each setting must explicitly define whether child scopes may override it.

Root-only settings are never overridable.

## Global uniqueness

Resolved use-case IDs must be globally unique across the entire workspace.

Scope boundaries never permit duplicate full IDs.

Duplicate resolved IDs make the workspace invalid.

## Summary

```text
workspace root
   |
   +-- root use-cases.yml
   |      +-- repo-wide policy
   |      +-- root prefix
   |      +-- root definition directory
   |
   +-- child scopes
   |      +-- explicit scope prefix
   |      +-- own definition directory
   |
   +-- optional root use-cases-bridge.yml
   |      +-- helpers only
   |
   +-- one root .use-cases/
          +-- generated outputs only
          +-- runs/<run-id>/ evidence folders
```

Identity comes from YAML.

Ownership comes from nearest scope.

Paths use one repo-root coordinate system.

Filesystem structure is organisational, not semantic.
