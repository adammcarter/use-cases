# 09 — Workspace Loading

**Phase:** 2 — Core Engine  
**Status:** Specification (locked)

## 1. Purpose

Workspace loading converts a filesystem workspace into a deterministic canonical revision of the long-lived mutable Workspace Model for the rest of the engine.

```text
filesystem
    |
    v
discover
    |
parse + validate
    |
resolve
    |
canonicalize
    |
    v
WorkspaceModel
```

The loader is responsible for understanding the workspace structure: scopes, use-case definitions, links (markers, manual bindings, resources), groups, and the optional bridge settings.

It does **not** run tests, run commands, or call transformers' results job.

`use-cases validate` is the loader on its own: it loads the workspace exactly as every other request does, reports whether it is valid (use cases, groups, bridge settings and links), and runs no test and writes nothing. An INVALID workspace fails it, as it fails every other request. Getting verdicts from tests is `use-cases verify` (chapter 13).

---

## 2. Core invariant

Correctness is the primary requirement.

```text
Correctness
    |
Determinism
    |
Minimal I/O
    |
Safe parallelism
    |
Performance
```

A faster incorrect, partial, stale, or nondeterministic load is unacceptable.

Performance optimizations MUST preserve exactly the same canonical result and diagnostics as an uncached serial load.

---

# 3. Entry point

The core loader receives an explicit workspace root.

```text
loadWorkspace(root: path)
```

The core MUST NOT search upward from the current working directory.

CLI, MCP, agent, IDE, or other wrappers MAY provide convenience root discovery before invoking the core.

---

# 4. Canonical workspace root

The supplied root MUST resolve to an existing directory.

Before any workspace processing, the loader resolves it to one canonical absolute directory.

Conceptually:

```text
supplied path
    |
normalize . / ..
    |
resolve filesystem identity
    |
    v
canonical workspace root
```

The canonical root becomes the filesystem boundary for the workspace.

No workspace-owned path may resolve outside it unless another specification explicitly permits that behaviour.

The original supplied path MAY be retained for diagnostics, but MUST NOT be used as semantic identity.

---

# 5. Root configuration

The loader MUST first read:

```text
<workspace-root>/use-cases.yml
```

Exactly one root scope is required.

Missing, unreadable, malformed, schema-invalid, or unsupported root configuration makes the workspace INVALID.

The root configuration MUST declare:

```yaml
schema_version: 1
root: true
```

`root: true` appears in the root configuration and nowhere else in the workspace. A child scope's configuration never has it; a folder whose configuration has it is a separate workspace (chapter 04).

Unsupported schema versions MUST be rejected.

The loader MUST NOT:

- silently downgrade a newer schema
- automatically migrate it
- guess its meaning
- partially interpret an unsupported schema

Because root configuration controls workspace discovery, a root configuration that cannot safely be interpreted prevents normal workspace discovery.

---

# 6. Scope discovery

Scope discovery and use-case definition discovery are separate operations.

A **scope** is any directory containing:

```text
use-cases.yml
```

The root scope is discovered explicitly from the supplied root.

Child scopes are discovered by scanning below the workspace root.

Directory symlinks MUST NOT be followed during scope discovery.

The complete scope set MUST be discovered before parent/child relationships are resolved.

---

## 6.1 Deterministic scope tree

After all scopes are discovered:

1. normalize their repo-relative paths
2. sort deterministically
3. assign each child to its nearest ancestor scope

```text
all scopes
    |
sort
    |
nearest ancestor
    |
    v
scope tree
```

Filesystem enumeration order MUST NOT affect the resulting tree.

---

## 6.2 Invalid child scopes

Every discovered child scope is part of the workspace.

A malformed or invalid child scope MUST NOT be silently skipped.

It makes the workspace INVALID.

Where safe, loading SHOULD continue so independent diagnostics from other scopes can also be reported.

---

# 7. Discovery exclusions

Repository-wide discovery exclusions are configured at the root.

They are applied before scope or definition discovery enters an excluded tree.

```text
workspace
    |
apply discovery.exclude
    |
    v
visible discovery tree
```

Excluded directories are invisible to:

- child-scope discovery
- use-case definition discovery

The loader SHOULD prune excluded trees before traversing them rather than discover content and discard it later.

This is both more efficient and more deterministic.

---

# 8. Root-only configuration

Repository-wide policy remains owned by the root scope.

Current root-only configuration includes:

- `freshness`
- `discovery`
- `sign_off`

A child scope attempting to declare a root-only setting is INVALID.

The loader MUST NOT silently ignore the child declaration.

---

# 9. Scope configuration resolution

Each scope declares its own `schema_version`.

Schema versions are never inherited.

All scopes in the workspace MUST use the supported workspace schema version.

For settings that are defined as inheritable, the resolved configuration follows:

```text
nearest explicit value
        |
        v
parent
        |
        v
core default
```

By the time the workspace model revision is returned, inheritance MUST already be materialized.

Downstream stages receive effective configuration, not unresolved inheritance instructions.

---

# 10. Namespace resolution

Filesystem structure is not identity.

Use-case identity is produced from explicit authored prefixes and IDs.

For each object the loader retains both:

```text
authored identity pieces
resolved identity
```

Example:

```text
scope prefix: auth
file prefix:  login
local id:     success

resolved:
auth.login.success
```

The loader MUST preserve enough authored information to produce precise diagnostics and future editing/migration tooling.

Resolved identity is what the engine uses semantically.

---

# 11. Definition discovery

Each scope has:

```text
use_cases_dir
```

If omitted, it defaults to:

```text
use-cases
```

`use_cases_dir` is relative to the scope directory.

A `use_cases_dir` that does not exist is read as an empty one (chapter 04).

It MUST NOT escape that scope.

Definition files are discovered recursively beneath that directory.

Recognized extensions are:

```text
.yml
.yaml
```

Every matching file in the owned definition tree is treated as a use-case definition file.

The loader MUST NOT guess whether a YAML file "looks like" a use-case file.

Therefore:

```text
use-cases/
  login.yml        definition
  payments.yaml    definition
  notes.yml        definition
```

If `notes.yml` does not satisfy the definition schema, the workspace is INVALID.

---

## 11.1 Child-scope boundaries

A child scope MUST NOT sit inside another scope's `use_cases_dir` (chapter 04). A `use-cases.yml` found there makes the workspace INVALID, and the message names it.

A child scope that needs its own definitions sits beside the parent's `use_cases_dir`, never inside it.

This keeps every definition owned by exactly one scope.

So nothing in or around a `use_cases_dir` is skipped silently. Each of these is INVALID, and the message names the path:

- any `use-cases.yml` inside a `use_cases_dir`, `root: true` included
- two scopes whose `use_cases_dir`s are the same folder, or one inside the other
- a `use_cases_dir` that is a file, not a folder
- a `use_cases_dir` inside an excluded tree (the built-in exclusions or `discovery.exclude`)
- a `use_cases_dir`, or a `use-cases.yml`, whose spelling matches the disk only when case or Unicode form is ignored (§19); the message names the on-disk spelling
- an exclusion that reaches inside a `use_cases_dir`: a `use_cases_dir` is read whole, and exclusions are for the code around it
- an entry in a `use_cases_dir` that is not a plain file or folder (a pipe, a socket), or whose name no path can spell
- a child scope in a folder whose name no path can spell (§6.2)

---

# 12. Symlinks

Discovery never follows a symlink, to a file or a folder (chapter 04).

```text
folder symlink                                   not entered
any symlink inside a use_cases_dir               INVALID, the message names it
a use_cases_dir that is, or sits behind, one     INVALID
a use-cases.yml that is a symlink                INVALID, never read
```

A symlink in a `use_cases_dir` is INVALID because every YAML entry there must be a definition, and a symlink is only its target text: a Windows checkout without symlink support writes that text into a plain file. Refusing it everywhere gives the same answer on every system.

---

# 13. Definition processing

The loader first discovers the complete definition file set.

It then:

1. reads each file
2. parses YAML
3. validates its schema
4. records source provenance
5. applies defaults
6. resolves namespace prefixes
7. resolves full IDs
8. performs non-executing semantic validation
9. canonicalizes the resulting model

Resolution MUST NOT depend on discovery order.

---

# 14. YAML model

Authored YAML may use normal YAML anchors and aliases.

They are authoring conveniences only.

After parsing, the document MUST resolve to ordinary JSON-compatible values:

```text
object
array
string
number
boolean
null
```

Alias identity has no semantic meaning in the canonical model.

Recursive aliases or structures that cannot be reduced safely to this data model are INVALID. Concretely, a file is INVALID when it nests deeper than 64 levels, or when its aliases expand it to more than 100,000 values: every reader then stops at the same place, and no file can make a reader run out of memory or stack.

Each file holds one YAML document. A second document, after a `---`, is INVALID.

A tag (`!!str 42`, `!note`, any `!`) is INVALID: values are written plainly, and text that would read as something else is quoted (below). The merge key `<<` is INVALID: YAML 1.1 merges with it and YAML 1.2 reads it as text.

A key is text. An unquoted key that YAML 1.2 reads as a number, a boolean or null (`1:`, `01:`, `true:`, `~:`) is INVALID and must be quoted, so no reader can merge `1` and `01` into one key.

A value is a JSON value. `.inf`, `.nan` and a number too large for a 64-bit float are INVALID unquoted.

Multi-line text (`|` and `>`) reads the same in every YAML version and is allowed. A UTF-8 byte order mark at the start of a file is ignored. A value whose text starts with a byte order mark (U+FEFF), written or escaped, is INVALID: readers drop it, so it would not be the same text everywhere. An unquoted `?` in a list or mapping written on one line (`[a?, b]`) is INVALID and must be quoted: YAML readers read it differently.

Duplicate YAML mapping keys are INVALID.

The loader MUST NOT silently choose one duplicate value.

Values are typed by the YAML 1.2 core schema. A plain (unquoted) scalar, key or value, that YAML 1.1 would type differently is INVALID and must be quoted: `on`, `off`, `yes`, `no` in any case, sexagesimal numbers such as `1:30`, dates such as `2024-01-01`, `1e3`, `0o17`. So every YAML implementation, of either version, reads an accepted file one way.

In use case files, and in use cases given to `save`, `apply`, `render` and `search --like`, unquoted text followed by a comment on its line is INVALID: YAML ends unquoted text at ` #`, so `- Check medal #4 shows` would silently read as `Check medal`. The error names the line and says to quote the whole text, or to put the comment on its own line. A comment after quoted text, or on its own line, is fine; settings files keep their end-of-line comments.

Every authored file is checked against its published schema as it loads (docs/schemas/authored). A value of the wrong type is INVALID, never a silent DRAFT.

---

# 15. Parallel parsing

Independent definition files MAY be read, parsed, and schema-validated concurrently.

```text
file A ----\
file B -----+--> parallel parse/validate
file C ----/
                 |
                 v
          deterministic merge
```

Concurrency MUST NOT affect:

- resolved IDs
- canonical ordering
- diagnostics
- fingerprints
- semantic results

The output of parallel loading MUST be equivalent to serial loading.

---

# 16. Stable processing order

Canonical ordering MUST be independent of task scheduling or filesystem enumeration.

Within a scope:

1. definition files are ordered by normalized workspace-relative path
2. use cases inside a definition file retain authored YAML order

Global identity resolution happens only after the authored model has been collected.

The engine MUST NOT assign semantic meaning based on load order.

---

# 17. Global identity resolution

After namespace composition, resolved use-case IDs are checked globally across the workspace.

Duplicate full IDs are INVALID.

```text
all authored definitions
        |
resolve prefixes + IDs
        |
global duplicate check
```

Duplicate detection MUST happen against resolved full identity, not only local file or scope identity.

---

# 18. Provenance

Every resolved object MUST retain sufficient source provenance.

At minimum, where applicable:

```text
source file
source scope
authored local ID
resolved full ID
```

Source position SHOULD also be retained when available from the parser.

Provenance is diagnostic metadata.

It is not semantic identity.

---

# 19. Path canonicalization

An authored path is written in its one canonical spelling, and is never normalized:

```text
bar          valid
./bar        INVALID: write bar
a//b         INVALID: write a/b
a/           INVALID: write a
foo/../bar   INVALID: `..` is never allowed
.            the workspace root, where a folder is meant
```

The message names the canonical spelling where there is one. So two spellings never name one file, and the path compared, resolved and fingerprinted is the text as written.

A path the workspace names must match the on-disk spelling exactly, case and Unicode form included, on every operating system (chapter 04). A path spelled differently is INVALID with a message naming the on-disk spelling, even on a file system that would have found it. So a workspace valid on one machine is valid on all, and every implementation fingerprints the same bytes.

A file whose name holds a control character or is not valid UTF-8 cannot be named in a link key. Marker scanning skips it with a warning, and naming it is INVALID.

Path rules defined elsewhere remain unchanged:

- workspace references are workspace-root-relative
- `use_cases_dir` is scope-relative
- paths may not escape their permitted boundary

---

# 20. Links

Links connect use cases and routes to repository content. Every kind of link is optional (chapter 08).

The loader resolves three sources, all without executing anything:

```text
manual bindings   authored in use-case YAML   -> validated, resolved to file + range
resources         authored on routes          -> validated, resolved to file set
markers           found in repository content -> scanned, paired, resolved to file + range
```

## 20.1 Manual bindings

For every manual binding the loader checks the rules of chapter 08:

- the file exists and is inside the canonical workspace root (a symlink is never followed: a binding to one tracks its target text, chapter 04)
- `start` and `end` are both present or both absent
- range positions are 1-based, inclusive, and inside the file; columns count code points (chapter 08)
- range bindings target text; whole-file bindings may target binary content
- `kind` is `manual`; a YAML binding with `kind: marker` is INVALID ("markers are found in the code and need no entry")

A violation makes the workspace INVALID.

A binding may name a file inside an excluded folder (chapter 04). It stays valid and warns that it points at excluded content.

## 20.2 Resources

For every route resource the loader checks the rules of chapter 06:

```text
kind: file   missing file        -> INVALID
kind: glob   malformed pattern   -> INVALID
kind: glob   zero matches        -> INVALID
kind: glob   one or more matches -> valid
```

Glob expansion is deterministic and sorted by canonical workspace-relative path.

## 20.3 Marker scan

The loader scans visible repository text for marker sentinels as chapter 08 defines.

- The scan respects discovery exclusions and never leaves the workspace root. So do resource globs, which match only files the scan reads (chapter 11 §42). A manual binding or a file resource may name a path inside an excluded folder (§20.1).
- It ignores Use Cases-owned content: every `use-cases.yml`, `use-case-groups.yml`, `use-cases-bridge.yml`, every discovered definition file, and `.use-cases/**`.
- Every file that is not excluded is read. There is no size cap, and a file is searched for the sentinel bytes before it is decoded.
- A file or folder the scan cannot read is INVALID, and the message names it: the link set would be unknown.
- Pairing, nesting, orphan, empty-region, and encoding rules are those of chapter 08.
- Pairing comes before the use-case lookup. An unpaired marker is INVALID even for an unknown use case; only a malformed marker id skips pairing, and it warns.
- A well-paired marker naming an unknown use case or unknown route is a diagnostic, not a link.

What the scan does with an entry that is not an ordinary readable file:

```text
a pipe, socket or device                                warned about and skipped, never opened
a file starting with a UTF-16 or UTF-32 byte-order mark  warned about: its markers cannot be read
a name with a control character or invalid UTF-8         skipped with a warning that escapes the name
a file with @use-case: that is not strict UTF-8          warned about as unsupported text (chapter 08)
```

The unsupported-text check runs only on files that hold the bytes `@use-case:`.

Markers need no YAML entry. A use case or route with no markers is valid.

## 20.4 Link transformers

Link transformers configured in the bridge settings (chapter 10) may add further links. Their links job is read-only and deterministic, so its output is part of the model revision. The core checks every link a links transformer returns (chapter 10 §11). A links transformer error stops the model from loading, because the link set would be unknown; it is reported with the transformer's name.

## 20.5 Link keys

Every resolved link receives a core-assigned key:

```text
<use_case>#[<route>.]<binding>@<file>:<start>
```

Keys are stable for identical content at identical locations and are what transformers use to address results (chapter 10).

---

# 21. Bridge settings

The optional root file:

```text
use-cases-bridge.yml
```

is loaded as part of the model revision (chapter 10).

```text
file absent  -> valid workspace; no helpers set up
file present -> must validate
```

It is root-only in v1. A `use-cases-bridge.yml` in a child scope is INVALID.

The loader validates its schema, validation IDs (never a name Windows reserves for a device), report names (a portable file or folder name, never a path), `working_dir` folders (existing, inside the workspace, never `.use-cases/`), and transformer references. It does not run any `run` command or results job.

---

# 22. Groups

The root-level optional file:

```text
use-case-groups.yml
```

is loaded as part of the workspace model revision.

Group resolution occurs only after all resolvable use-case full IDs are known.

```text
resolve use-case IDs
        |
        v
resolve group selectors
        |
        v
canonical groups
```

Downstream stages MUST NOT need to reopen the groups file.

Group rules remain as defined by the group specification (chapter 03).

---

# 23. Defaults and normalization

Equivalent authored configuration MUST produce equivalent canonical configuration.

Example:

```yaml
gates_verification: true
```

and omission of that field, where `true` is the defined default, become identical internally.

```text
authored YAML
    |
apply defaults
    |
normalize
    |
resolve
    |
canonical object
```

Downstream core stages consume canonical objects.

They MUST NOT independently reinterpret raw YAML defaults.

---

# 24. Canonical Workspace Model

A successful initial load creates a Workspace Model with one consistent canonical revision.

```text
WorkspaceModel
  root configuration
  resolved scopes
  resolved use cases
  resolved links (markers, manual bindings, resources, transformer links)
  resolved groups
  bridge settings (when present)
  provenance
  warnings / diagnostics metadata
  workspace fingerprint for the current revision
```

Tools may mutate the model through validated, atomic revision changes. Resolved links, group membership, authored state, and the workspace fingerprint must be recomputed or invalidated when their inputs change. Readers observe one consistent revision, never a partially applied edit.

The model records its last synchronized authored disk state and intentional unsaved edits. Saving is a separate explicit operation. Loading does not execute validation or implicitly save.

Downstream stages consume canonical model data. Synchronization is explicit; they do not independently reinterpret YAML. The verify flow (chapter 13) reads route fingerprints from a synchronized revision before and after it runs anything.

---

# 25. INVALID objects

Malformed or semantically invalid definitions do not become usable canonical objects.

Conceptually:

```text
safe definition
  -> DRAFT or READY canonical object

invalid definition
  -> diagnostics
  -> workspace INVALID
```

The loader MAY retain temporary partial parse structures internally for diagnostic purposes.

Those structures MUST NOT be exposed as usable canonical use cases.

---

# 26. Load failure contract

A workspace load has two externally meaningful outcomes.

```text
VALID
  -> WorkspaceModel
  -> zero or more warnings

INVALID
  -> diagnostics
  -> no usable WorkspaceModel
```

The API MUST NOT expose a partially valid workspace as though it were safe for downstream validation.

---

# 27. Diagnostic collection

The loader SHOULD report as many independent problems as can safely be determined in one load.

It SHOULD NOT fail on the first child-definition error when the remaining workspace can still be inspected safely.

However, it MUST NOT continue into stages that require configuration that could not be safely interpreted.

---

## 27.1 Deterministic diagnostic ordering

Parallel processing MUST NOT make diagnostic ordering unstable.

Diagnostics are sorted deterministically.

Key:

```text
source path
-> line, as a number (line 9 before line 10)
-> diagnostic code
```

Severity does not alter this ordering.

The refusal's message (chapter 16 §5) gives each problem on its own line, in this order, each starting with its file (and line, where there is one).

This makes:

- tests reproducible
- CLI output stable
- CI logs comparable
- agent consumption deterministic

---

# 28. Model synchronization and revision semantics

The Workspace Model is long-lived and mutable. A consistent read of a particular model revision does not change beneath its reader.

External authored-file changes are reconciled against the last synchronized disk state:

- With no conflicting unsaved model edit, refresh the affected authored data and atomically publish a validated revision.
- With conflicting unsaved edits, report a synchronization conflict. Do not silently overwrite either side or guess a merge.
- Invalid external authored state must be surfaced as current diagnostics; a retained last-valid revision must not masquerade as the current valid workspace.

Tool edits update model semantics without implicitly saving. A save must detect intervening conflicting disk changes before overwriting authored files.

Before the verify flow reads route fingerprints, it synchronizes as chapter 13 requires and reads one consistent revision.

```text
authored files <-> mutable Workspace Model
                         |
               consistent revision read
                         |
          route fingerprints for the verify flow
```

Nothing is frozen or copied. Tests run in the real project; chapter 13's guard decides whether a result still describes the code it was produced for.

---

# 29. Concurrent filesystem mutation

The loader MUST avoid knowingly returning a mixed workspace model revision assembled from incompatible filesystem states.

It records sufficient identity/change information while reading workspace inputs and performs a final consistency check before publishing the model revision.

The consistency check covers both:

- files already discovered, including linked files, resource files, and bridge settings
- the discovered workspace structure itself

Examples of relevant changes:

```text
definition modified
definition deleted
definition added
scope added
scope removed
configuration replaced
linked file modified
```

If the loader determines that the workspace changed materially during loading, that load is rejected.

The caller may perform a fresh load.

The core does not automatically retry indefinitely.

---

## 29.1 Discovery-set consistency

A final lightweight discovery verification confirms that the relevant discovered file/scope set still represents the workspace being returned.

```text
initial discovery set
        |
load + resolve
        |
final consistency check
        |
    +---+---+
    |       |
 stable   changed
    |       |
revision   reject
```

This protects against a new definition or scope appearing midway through a load.

---

# 30. I/O efficiency

On the uncontended fast path, an authored YAML file SHOULD have its content bytes read once.

That read should supply everything possible for:

- parsing
- schema validation
- provenance
- content identity required by the loader

Repeated independent reads of the same file for separate loader phases should be avoided.

Correctness overrides this optimization.

If proving model revision consistency requires additional filesystem verification, the loader MUST perform it rather than return an uncertain result.

---

# 31. Cache policy

Loader caching is optional.

A cache is never authoritative.

```text
cache candidate
      |
prove source identity still matches
      |
    +---+---+
    |       |
 valid   uncertain
    |       |
 reuse    re-read
```

If cache validity cannot be proven, the loader MUST fall back to the filesystem source of truth.

Deleting the cache MUST never change workspace semantics.

A cached and uncached load of the same workspace state MUST produce the same canonical model revision.

---

# 32. Workspace fingerprint

Every successfully resolved model revision has a deterministic workspace fingerprint. It identifies that revision, not the lifetime of the mutable model.

```text
canonical workspace model
          |
          v
workspace fingerprint
```

It can later support:

- cache validation
- result provenance
- detecting workspace changes between engine stages

The exact canonical encoding and digest rules belong to the fingerprint specification (chapter 11) and are not duplicated here.

---

# 33. Loader non-goals

Workspace loading does NOT:

- run bridge `run` commands
- call a transformer's results job
- execute scripts
- perform procedures
- launch tests
- determine pass / fail
- compute or record results
- treat cache state as authoritative
- search upward for the workspace root

It is fundamentally:

```text
discover
parse
validate
resolve
canonicalize
publish model revision
```

---

# 34. Reference load sequence

A conforming implementation behaves conceptually like this:

```text
1. canonicalize supplied workspace root

2. load root use-cases.yml
   -> parse
   -> schema validate
   -> verify schema version

3. resolve root discovery policy

4. discover complete scope set
   -> prune excluded trees
   -> do not follow directory symlinks

5. sort scopes deterministically

6. build parent/child scope tree

7. validate child configurations

8. resolve effective scope configuration
   + namespace prefixes

9. discover each scope's definition files
   -> respect child-scope boundaries
   -> .yml / .yaml
   -> canonicalize file identity

10. load definition files
    -> parallel where safe
    -> parse
    -> schema validate
    -> record provenance

11. apply authored defaults

12. compose namespaces + full IDs

13. detect global duplicate IDs

14. perform required non-executing semantic checks

15. load optional root use-cases-bridge.yml
    -> parse
    -> schema validate

16. resolve manual bindings and resources

17. scan markers

18. run link transformers' links job (when configured)

19. assign link keys

20. resolve groups

21. build canonical resolved model

22. deterministically order diagnostics/output

23. perform final workspace consistency check

24. compute model revision fingerprint

25. create WorkspaceModel or atomically publish its synchronized revision
```

---

# 35. Performance contract

The loader should aggressively optimize work that does not affect semantics.

Preferred strategies include:

- prune excluded trees before traversal
- avoid rescanning directories
- avoid duplicate content reads
- parse independent files in parallel
- resolve globally only after collection
- cache only when validity is proven
- canonicalize once and reuse canonical values
- retain filesystem identity information during discovery
- keep downstream stages on consistent canonical model revisions rather than independently reopening YAML

But:

```text
performance optimization
        |
        v
changes semantic result?
        |
   yes ------> forbidden
   no  ------> allowed
```

---

# 36. Required properties

A correct implementation of workspace loading MUST be:

### Accurate
The loaded revision represents the authored workspace according to the specification.

### Deterministic
Equivalent workspace state produces equivalent canonical output regardless of filesystem traversal order or concurrency scheduling.

### Complete
All visible scopes and definition files are considered.

### Strict
Malformed or ambiguous authored state is not silently guessed.

### Consistent and mutable
The Workspace Model changes through coherent revisions. A reader of one revision never sees a partially applied edit.

### Performant
Unnecessary traversal, parsing, allocation, and I/O are avoided without weakening correctness.

### Actor-agnostic
The loader has no concept of whether a human, CLI, agent, MCP server, IDE, or another system requested the load.

---

# 37. Final model

```text
                 explicit root
                      |
                      v
              canonical boundary
                      |
                      v
              deterministic scan
                 /           \
              scopes       definitions
                 \           /
                  \         /
                   v       v
                 parse + validate
                       |
                       v
                  resolve IDs
                       |
                       v
          resolve links + bridge settings
                       |
                       v
                 resolve groups
                       |
                       v
                 canonicalize
                       |
                       v
              consistency check
                       |
                       v
             consistent model revision
```

The Workspace Model is the canonical mutable in-memory representation. Authored files remain the durable source of truth.
