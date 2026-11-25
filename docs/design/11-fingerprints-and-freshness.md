# 11 — Fingerprints + Freshness

**Phase:** 2 — Core Engine  
**Status:** Specification (locked)

## 1. Purpose

Freshness answers one question:

> Does an existing validation result still apply to the current validation route?

The answer is derived from a deterministic fingerprint of the route and every declared input that affects what that route validated.

```text
current route inputs
        |
        v
   fingerprint
        |
        +---- matches previous result ----> applicable
        |
        +---- differs --------------------> stale
```

Freshness does not determine whether behaviour is correct.

Validation does that.

Freshness determines whether existing validation evidence still applies.

---

Examples in this chapter use a small Swift project. Nothing in the rules depends on it: the shapes are the same for any language and tool.

## 2. Core model

Every READY validation route has a deterministic fingerprint.

Conceptually:

```text
route meaning
+
covered behaviour
+
route definition (type, covers, gating, procedure)
+
implementation link content
+
validation link content
+
resources
+
freshness policy
        |
        v
route fingerprint
```

Links are optional (chapter 08). A route with no links still has a fingerprint; it simply tracks only the use case's own wording.

A stored result records the route fingerprint it validated.

Later:

```text
stored fingerprint == current fingerprint
```

means the result is applicable to the current route state.

---

## 3. Core guarantees

Fingerprinting MUST be:

- deterministic
- content-addressed
- independent of filesystem enumeration order
- independent of concurrency scheduling
- independent of YAML formatting
- independent of irrelevant authoring syntax
- reproducible across conforming implementations

Equivalent semantic inputs MUST produce the same fingerprint.

Different fingerprint-relevant inputs MUST be expected to produce a different fingerprint.

---

## 4. Cryptographic hash

V1 uses:

```text
SHA-256
```

Reasons:

- universally available
- hardware accelerated on common platforms
- stable across languages
- widely audited
- sufficient performance for repository content hashing
- avoids requiring a specialised hashing dependency

Fingerprint formats are versioned so the algorithm can change in a future format version without ambiguity.

Example external representation:

```text
uc-route-v1-sha256:<64 lowercase hexadecimal characters>
```

Other fingerprint kinds use their own domain prefix.

Examples:

```text
uc-content-v1-sha256:...
uc-route-v1-sha256:...
uc-workspace-v1-sha256:...
```

---

## 5. Fingerprint versioning

Fingerprint format version is independent of:

```text
schema_version
```

Example:

```text
schema_version: 1
fingerprint format: route-v1
```

A future core may support:

```text
schema_version: 1
fingerprint format: route-v2
```

without changing the authored use-case schema.

A result produced using an incompatible fingerprint format cannot verify a route using another format.

---

## 6. Domain separation

Different fingerprint kinds MUST use different hash domains.

Conceptually:

```text
"use-cases/content/v1"
"use-cases/route/v1"
"use-cases/workspace/v1"
"use-cases/promise/v1"
```

The domain identifier is included in the hashed material.

This prevents a digest from one fingerprint kind being accidentally interpreted as another.

---

## 7. Canonical structured encoding

Structured fingerprint input is serialized deterministically before hashing.

V1 canonical structured encoding uses canonical JSON semantics:

- UTF-8
- object keys sorted deterministically
- no insignificant whitespace
- deterministic string escaping
- integers serialized canonically
- arrays preserve semantic order
- unordered semantic sets are explicitly sorted before serialization

No floating-point values are currently required by route freshness inputs.

Object/map insertion order MUST NOT affect fingerprints.

---

## 8. Content fingerprints

Raw or normalized content is first reduced to a reusable content fingerprint.

Conceptually:

```text
content bytes
    |
normalization
    |
domain-separated SHA-256
    |
    v
ContentFingerprint
```

A content reference used inside a larger fingerprint contains at least:

```text
algorithm
digest
byte length
```

The byte length refers to the normalized byte sequence actually hashed.

This allows large files to be streamed rather than embedded into route fingerprint payloads.

---

## 9. Freshness policy

Freshness policy is configured at the root `use-cases.yml`.

Example:

```yaml
freshness:
  binding_identity: content
  normalization:
    ignore: [line-endings]
```

The policy is repository-wide.

Child scopes cannot override it.

---

## 10. Binding identity policy

V1 supports:

```text
content
content-and-locator
```

Default:

```text
content
```

---

## 10.1 `content`

Freshness follows the resolved linked content.

Moving that content without changing its identity or bytes does not stale validation.

Example:

```text
src/old.swift lines 20-40
          |
        moved
          |
src/new.swift lines 80-100
```

If the same binding ID still resolves to identical content:

```text
not stale
```

This is the default because implementation location is normally incidental to behaviour.

---

## 10.2 `content-and-locator`

Freshness follows both:

```text
resolved content
+
resolved locator
```

Moving the same content therefore stales the route.

This is useful when physical location is considered meaningful.

---

## 11. Binding ID remains identity

`binding_identity: content` does **not** mean binding IDs are ignored.

A binding ID is persistent identity, whether it comes from a marker, a manual binding, or a link transformer (chapter 08).

Changing:

```text
database-write
```

to:

```text
save-operation
```

means the old link was removed and a new link was created.

Therefore binding IDs participate in route fingerprints.

A binding rename stales affected routes even when the linked bytes are identical.

---

## 12. Normalization policy

V1 supports:

```yaml
freshness:
  normalization:
    ignore:
      - line-endings
      - whitespace
```

Both entries are optional.

Default, when `normalization` or its `ignore` is omitted:

```yaml
ignore: [line-endings]
```

so an LF and a CRLF checkout of the same commit agree, which matters once evidence moves between machines (chapter 12 §32). `ignore: []`, written out, means exact comparison.

When a link's content is several pieces (a marker region with nested sentinel lines left out), the pieces are joined first and the joined bytes are normalized, so a CR ending one piece and an LF starting the next are one line ending.

The ignore list is semantically a set.

Its authored order has no meaning.

Duplicate entries are invalid.

Unknown normalization names are invalid.

---

## 13. Exact mode

With:

```yaml
ignore: []
```

content is fingerprinted exactly. This is not the default: by default line endings are ignored (§12).

For whole-file binary or text content:

```text
different byte
    |
    v
different content fingerprint
```

---

## 14. Line-ending normalization

With:

```text
line-endings
```

text content normalizes:

```text
CRLF -> LF
CR   -> LF
LF   -> LF
```

before hashing.

No other content is changed.

Binary content remains exact.

---

## 15. Whitespace normalization

With:

```text
whitespace
```

ASCII whitespace is ignored when fingerprinting text content.

The ignored byte/code-point set is exactly:

```text
TAB   U+0009
LF    U+000A
VT    U+000B
FF    U+000C
CR    U+000D
SPACE U+0020
```

These characters are removed before hashing.

Other Unicode whitespace is not implicitly ignored.

This avoids platform- or Unicode-version-dependent behaviour.

Because whitespace may be semantically meaningful in some languages and file formats, enabling this option is an explicit repository policy decision.

---

## 16. Normalization order

When multiple normalization rules are enabled, they execute in fixed core-defined order.

V1:

```text
1. line-endings
2. whitespace
```

The order written in YAML does not affect the result.

Because `whitespace` removes line-ending whitespace anyway, enabling both may be redundant, but remains valid.

---

## 17. Text versus binary content

Normalization applies only to content represented as text.

Content known to be textual through link resolution is normalized as text.

For whole-file resources or manual bindings:

- strict UTF-8 content is treated as text for normalization
- otherwise content is treated as binary and hashed exactly

An optional UTF-8 BOM does not cause the file to become binary.

Exact mode still fingerprints the original bytes exactly.

The core MUST NOT perform heuristic character-set guessing during freshness calculation.

---

## 18. Normalization scope

Freshness normalization applies only to resolved link and resource content.

It does **not** normalize:

- scenario text
- intent
- procedure steps
- IDs
- YAML strings generally
- paths

Those are already canonical structured values.

---

## 19. Route fingerprint payload

Every route fingerprint includes these semantic categories:

```text
identity
freshness policy
use-case intent
covered scenarios
route definition
implementation links
route validation links
route resources
```

Each category is described below.

---

## 20. Route identity

The route fingerprint includes:

```text
resolved use-case ID
route ID
```

Results are already keyed by those identities, but including them in the fingerprint prevents accidental cross-identity reuse.

Changing the use-case or route ID creates a different validation identity.

Existing results for the previous identity do not transfer.

---

## 21. Intent

The use case's:

```text
intent
```

participates in every route fingerprint for that use case.

Changing intent therefore stales every existing route.

Reason:

```text
intent = why the validated behaviour exists
```

A changed intent can change the meaning of otherwise identical observable behaviour.

---

## 22. Covered scenarios

A route fingerprints only the scenarios it covers.

For each covered scenario, the fingerprint includes:

```text
scenario ID
given[]
when[]
then[]
```

The order within:

```text
given
when
then
```

is preserved.

Those lists are behavioural sequences.

---

## 23. `covers` ordering

`covers` is semantically a set of scenario IDs.

Therefore these are equivalent:

```yaml
covers:
  - success
  - wrong-password
```

and:

```yaml
covers:
  - wrong-password
  - success
```

The core sorts covered scenario identity deterministically before fingerprinting.

Reordering `covers` alone does not stale the route.

Changing membership does.

---

## 24. Scenario changes

Changing a scenario stales only routes that cover that scenario.

Example:

```text
scenario A changed

route 1 covers A -> stale
route 2 covers A -> stale
route 3 covers B -> unchanged
```

This keeps recomputation precise.

---

## 25. New scenarios

Adding a new scenario does not automatically change existing route fingerprints.

However READY requires every scenario to be covered by at least one gating route.

Therefore:

```text
new uncovered scenario
        |
        v
use case becomes DRAFT
```

until gating coverage is supplied.

Once a route's `covers` membership changes to include the new scenario, that route's fingerprint changes.

---

## 26. Route definition

The fingerprint includes the route's canonical:

```text
type
covers
gates_verification
procedure
```

Therefore changes to any of these stale that route.

---

## 27. Validation type

Validation `type` participates even though type is classification rather than execution control.

Example:

```text
unit -> integration
```

stales the route.

Reason:

The validation claim itself has changed even if the same tests still prove it.

---

## 28. Gating changes

Changing:

```text
gates_verification
```

changes the route fingerprint.

Example:

```text
true -> false
```

The route becomes stale relative to its previous result, but it does not lower overall use-case verification status.

Example:

```text
false -> true
```

The route becomes stale and now participates in overall verification.

---

## 29. Procedure

A route's optional `procedure` participates in its fingerprint:

```text
setup[]
steps[]
reset[]
```

List order is preserved. Strings are exact.

Adding, removing, or editing a procedure stales that route.

Reason:

```text
procedure = how a person or agent performs the check
```

A changed procedure is a changed validation claim, even if the covered scenarios are identical.

A route without a procedure fingerprints `procedure` as absent (section 89.4).

---

## 30. Helpers do not participate

Nothing from the helpers ring (chapter 01) enters a route fingerprint:

```text
use-cases-bridge.yml
run commands and their flags
transformer names, programs, versions and settings
report names and where reports are written
test IDs and test names a transformer reports
```

Example:

```text
swift test --filter AuthTests
```

changed to:

```text
swift test
```

does not stale any route.

Freshness follows what the route validates, not how evidence happened to be produced. Which run produced a result is recorded in the result itself (chapter 12), not in its fingerprint.

If a tool or dependency version must stale evidence, declare the file that pins it as a resource, for example `Package.resolved`.

---

## 31. Implementation links

Every route fingerprints every implementation link belonging to its use case.

Implementation links come from:

```text
markers           <use-case-id>#<binding-id>
manual bindings   use_case.bindings[]
link transformers links with role: implementation
```

Therefore an implementation change can affect all validation routes for that use case.

```text
implementation link changes
        |
        +--> route A stale
        +--> route B stale
        +--> route C stale
```

Whether those stale routes affect overall use-case status depends on `gates_verification`.

---

## 32. Validation links

A route fingerprints only its own validation links.

Validation links come from:

```text
markers           <use-case-id>#<route-id>.<binding-id>
manual bindings   validation[].bindings[]
link transformers links with role: validation for this route
```

Therefore:

```text
route A test changes
        |
        +--> route A stale
        |
        +--> route B unchanged
```

This keeps freshness local.

---

## 33. Link contribution

Links are grouped by binding ID within their collection:

```text
implementation links  -> grouped per use case
validation links      -> grouped per route
```

Every binding contributes at least:

```text
binding ID
resolved linked content
```

Under:

```text
content-and-locator
```

it additionally contributes its source kind and locator identity.

Binding contributions are sorted deterministically by binding ID.

Several marker regions with the same marker identity form one binding. A binding ID claimed by two different sources in one collection, such as a manual binding and a marker, is INVALID (chapter 08).

Authored binding list order has no freshness meaning.

---

## 34. Marker content

For markers, the linked content is the content between:

```text
@use-case:<marker-id>
...
@use-case:end <marker-id>
```

The marker sentinel text itself is excluded.

If one marker identity resolves to multiple regions, every region participates.

Duplicate identical regions remain distinct contributions.

Adding or removing one identical region changes multiplicity and therefore stales affected routes.

---

## 35. Content-mode multi-region links

Under:

```text
binding_identity: content
```

multiple resolved regions are fingerprinted as a **multiset of normalized contents**.

They are canonicalized by content identity, not by source location.

Conceptually:

```text
region contents
    |
normalize each
    |
content fingerprint each
    |
sort content identities
    |
preserve duplicates
```

This is required so moving regions does not accidentally stale a content-identity link.

Example:

```text
A at file 1
B at file 2
```

moved to:

```text
B at file 1
A at file 2
```

still represents the same content multiset.

Locator movement therefore remains non-semantic in `content` mode.

---

## 36. Strict multi-region links

Under:

```text
binding_identity: content-and-locator
```

each region contributes:

```text
content
+
canonical locator
```

Locator ordering is deterministic:

```text
workspace-relative path
then start position
then end position
```

Moving a region therefore changes the fingerprint.

---

## 37. Manual bindings

For a whole-file manual binding:

```text
content mode
    -> binding ID + file content

strict mode
    -> binding ID + canonical path + file content
```

For a range:

```text
content mode
    -> binding ID + selected content

strict mode
    -> binding ID + canonical path + start/end + selected content
```

---

## 38. Link source

Under `content` mode, the source of a link does not affect freshness if:

- binding ID is unchanged
- resolved content is unchanged

For example, replacing a marker with a manual range that resolves to the same content does not itself stale the route.

Under `content-and-locator`, the source kind participates:

```text
marker
manual
transformer
```

---

## 39. Link transformer links

A link transformer (chapter 10) reports only:

```text
use case, route, binding ID, role, file, range
```

The core reads the linked content itself and fingerprints it exactly like any other link.

A transformer never supplies content, digests, or fingerprints.

Because the links job must be deterministic, the same repository state yields the same links and therefore the same fingerprints.

---

## 40. Empty links

A valid empty linked region fingerprints the empty content sequence.

It remains valid according to chapter 08 and may produce a warning.

Changing:

```text
empty -> non-empty
```

or:

```text
non-empty -> empty
```

changes the fingerprint.

---

## 41. Resources

Every route fingerprints its resolved resource set.

Resources are expanded before fingerprinting.

Resources count for freshness only. They never expect a validation result (chapter 07).

For each resolved resource file, the fingerprint includes:

```text
canonical workspace-relative path
normalized content fingerprint
```

Resource paths participate regardless of binding identity policy.

`binding_identity` applies only to links.

---

## 42. Glob resources

A glob contributes the files it currently resolves to.

A glob matches only files the code scan reads (chapter 09 §20.3). It never matches:

- a path the workspace excludes, built in or by `discovery.exclude`
- a file Use Cases owns: `use-cases.yml`, a definition file, `use-cases-bridge.yml`, `use-case-groups.yml`
- anything inside a nested workspace

An explicit resource path, not a glob, may name a file in an excluded folder.

A file's identity is its workspace path, never an inode. Two hard links are two files, so every checkout agrees. A symlink is its target text (chapter 04).

Matches are:

1. canonicalized
2. deduplicated by workspace path
3. sorted by workspace-relative path

The authored glob expression itself does not participate if it resolves to the same canonical resource set.

Example:

```text
fixtures/*.json
```

and another selector producing exactly the same files and paths produce the same resource contribution.

Freshness follows the resolved resource set.

---

## 43. Resource membership changes

Any resource membership change stales the route.

Examples:

```text
matched file added
matched file removed
matched file renamed
matched file content changed
```

All change the resource contribution.

---

## 44. Duplicate resource coverage

If multiple resource declarations resolve to the same workspace path, that file contributes once to the resolved resource set.

Overlap is not multiplied merely because multiple selectors reached it.

This makes resource semantics set-based rather than authoring-list-based.

---

## 45. Freshness policy participates

The canonical freshness policy itself participates in every route fingerprint.

This includes:

```text
binding_identity
normalization.ignore
fingerprint format version
```

Therefore changing repository freshness policy stales existing results.

This is deliberately conservative.

Evidence created under one interpretation of freshness is not silently reused under another interpretation.

---

## 46. Fields that DO affect route freshness

Summary:

```text
use-case ID
route ID
intent

covered scenario IDs
covered scenario given/when/then

route type
route covers membership
gates_verification
route procedure

implementation binding IDs
implementation linked content
implementation locators and source kinds when strict

route validation binding IDs
validation linked content
validation locators and source kinds when strict

resolved resources
resource paths
resource contents

freshness policy
fingerprint format
```

---

## 47. Fields that DO NOT affect route freshness

The following do not stale an otherwise equivalent route:

```text
use-case title
description
value_tier
out_of_scope

YAML comments
YAML whitespace
mapping key order
definition YAML file location

use-cases-bridge.yml
run commands
transformers and their settings
report names and where reports are written
reported test IDs

link locator in content mode
link source kind in content mode
marker sentinel text when resolved content/ID are unchanged

timestamps
diagnostics
previous results
result storage location
```

These values may still affect the workspace model, diagnostics, or result provenance.

They simply do not change whether a previous route validation still applies.

---

## 48. Why `out_of_scope` does not stale validation

`out_of_scope` documents deliberate boundaries.

It is not itself an asserted behaviour exercised by a validation route.

Therefore changing it does not invalidate evidence for already-declared scenarios.

If an out-of-scope behaviour becomes required, it should become behavioural contract material:

```text
scenario added
    |
coverage required
    |
validation required
```

That change then affects readiness and route freshness mechanically.

---

## 49. Route fingerprint computation

Conceptually:

```text
RouteFingerprintInput {
  fingerprint_version
  freshness_policy

  use_case_id
  route_id
  intent

  covered_scenarios[]

  route {
    type
    covers
    gates_verification
    procedure
  }

  implementation_links[]
  validation_links[]
  resources[]
}
```

The canonical structure is serialized deterministically and hashed using the V1 route hash domain.

---

## 50. Route fingerprints exist only for valid resolved routes

Freshness is meaningful only when the core can safely resolve the required inputs.

A route cannot obtain an authoritative current fingerprint when:

- a manual binding fails to resolve
- marker pairing is invalid
- a resource fails to resolve
- its use case is INVALID
- other required semantic resolution fails

If a configured link transformer fails, the full link set is unknown. No route in the workspace receives an authoritative fingerprint until the transformer succeeds; status reports the failure rather than guessing.

A READY route with no links at all has complete fingerprintable semantics.

DRAFT/INVALID state remains governed by the authored-state specification.

---

## 51. Result applicability

A result is applicable only when all of these match:

```text
use-case identity
route identity
compatible fingerprint format
route fingerprint
```

Status alone is never enough.

A historical:

```text
PASS
```

for different fingerprinted inputs cannot verify the current route.

---

## 52. Latest matching result

Result history is content-addressed by route fingerprint.

For the current fingerprint:

```text
find results for same use case + route
        |
        v
find results matching current fingerprint
        |
        v
choose latest matching result
```

"Latest" is defined by the deterministic result-store ordering specified by the results-storage specification, not by unreliable wall-clock comparison alone.

With run-folder storage, the engine reads valid sealed runs and chooses the matching result from the highest run ID. Run IDs are monotonically allocated by the workspace core; timestamps remain diagnostic metadata only.

This is allocation order, not completion order: an older run finishing late cannot override a newer matching sealed run. Active or interrupted unsealed runs do not contribute partial evidence. Storage corruption is reported as a storage error, not treated as empty history.

---

## 53. Reverting to a previously verified state

If a route returns to an exact previously fingerprinted state, its previous matching result becomes applicable again.

Example:

```text
state A -> PASS
state B -> stale / verify again
state A -> previous PASS applies again
```

No rerun is required solely because the repository temporarily moved through another state.

Freshness is content-addressed, not change-counter-addressed.

---

## 54. Multiple results for one fingerprint

If several results exist for the same route fingerprint, the latest matching result controls.

Example:

```text
fingerprint X -> PASS
fingerprint X -> FAIL
```

current X:

```text
FAILED
```

because the latest applicable result is FAIL.

If later:

```text
fingerprint X -> PASS
```

current X becomes:

```text
VERIFIED
```

---

## 55. No matching result

For a READY route:

```text
no result for route identity
    -> unverified
```

If results exist for that route identity but none match the current fingerprint:

```text
stale
```

This distinction preserves:

```text
unverified = no evidence yet
stale      = evidence exists, but for another state
```

---

## 56. Matching result statuses

When the latest result matches the current fingerprint:

```text
PASS       -> verified
FAIL       -> failed
INCOMPLETE -> incomplete
ERROR      -> error
```

This uses the existing runtime state model.

---

## 57. Unsupported historical fingerprint formats

A historical result using a fingerprint format the current core cannot compare does not verify the route.

If prior evidence exists for the same route identity but none is comparable/current:

```text
stale
```

The engine MUST NOT guess equivalence across unknown fingerprint formats.

---

## 58. Result age

V1 has no automatic time-to-live for validation results.

A matching result remains applicable regardless of age.

Timestamp is evidence metadata, not freshness input.

If a future policy introduces expiry, it must be explicit and independently specified.

---

## 59. Overall use-case status

Freshness is first derived per route.

Only gating routes contribute to overall READY use-case runtime status.

Existing ordering remains:

```text
verified
stale
unverified
incomplete
error
failed
```

from best to worst.

The overall READY use-case status is the worst gating-route status.

Non-gating routes retain their own freshness/runtime status but do not lower the use-case result.

---

## 60. Implementation change fan-out

Because all routes include implementation links:

```text
implementation content changes
        |
        v
all route fingerprints change
```

All affected routes become stale if they have previous evidence.

Only gating routes affect the use-case aggregate.

This applies equally to automated and procedural routes.

---

## 61. Validation change locality

Changing a route's validation link, procedure, type, coverage, gating flag, or resources changes only that route's fingerprint.

Other routes remain current unless they share another changed input.

---

## 62. Intent fan-out

Intent belongs to the whole use case.

Therefore:

```text
intent changes
    |
    v
every route fingerprint changes
```

This is deliberate.

---

## 63. Metadata changes

Changing:

```text
title
description
value_tier
out_of_scope
```

does not affect route fingerprints.

Therefore an otherwise verified use case remains verified.

The canonical workspace fingerprint may still change because the workspace model changed.

---

## 64. Workspace fingerprint

Each consistent Workspace Model revision also has a deterministic semantic fingerprint. Mutation invalidates that revision's cached fingerprint; this is not an identity for the model's lifetime.

External form:

```text
uc-workspace-v1-sha256:<digest>
```

This fingerprint represents the canonical authored/resolved workspace model.

It is separate from route freshness.

---

## 65. Workspace fingerprint includes

The workspace semantic fingerprint includes canonical model information such as:

```text
schema/configuration
scope structure
effective repository policies
resolved use cases
metadata
scenarios
validation definitions
manual bindings and resources as authored
resolved groups
```

It follows the same deterministic canonical structured encoding rules.

---

## 66. Workspace fingerprint excludes

It excludes:

```text
provenance/source locations
diagnostics
warnings
timestamps
runtime results
.use-cases generated data
filesystem traversal order
YAML comments/formatting
use-cases-bridge.yml
```

It also excludes external file bytes: marker regions, manual binding content and resource content.

Those are represented by route fingerprints rather than the authored workspace model fingerprint.

Bridge settings belong to the helpers ring (chapter 01). They are loaded by chapter 09 but never change the core model's identity.

Therefore:

```text
workspace fingerprint
    = semantic authored/resolved model identity

route fingerprint
    = validation freshness identity
```

---

## 67. File movement and workspace fingerprint

Moving a definition YAML file without changing its resolved canonical model does not change the semantic workspace fingerprint.

Provenance changes.

Semantics do not.

This mirrors the overall rule:

```text
authoring layout != semantic identity
```

---

## 68. Fingerprint versus correctness

A matching fingerprint means:

> The inputs defined by this freshness specification are the same.

It does **not** mean:

- the validation was logically sufficient
- the test itself was correct
- the external world has not changed
- a tool or dependency outside declared inputs is identical
- a human procedural judgment would necessarily be repeated

Fingerprints establish evidence applicability, not truth.

---

## 69. Declared-input boundary

V1 freshness is exact with respect to inputs the core explicitly models.

Those include:

- route contract
- declared links: markers, manual bindings, link transformer links
- declared resources
- freshness policy

It does not attempt to fingerprint the entire external machine or world.

Examples of undeclared external state include:

```text
installed compiler version
test command and its flags
transformer versions
system frameworks
network services
database contents
undeclared files
process environment
external APIs
current OS state
```

If such state affects validation and must participate in freshness, it should be made explicit through resources.

The core MUST NOT pretend it can infer undeclared dependencies perfectly.

---

## 70. Toolchains and commands

Run commands, their environment, and the tools they launch are helpers (chapter 14). None of them are fingerprinted.

Hashing tools or environments would:

- create large amounts of irrelevant staleness
- capture machine-specific noise
- risk secret-sensitive behaviour
- still fail to model every external dependency

Repositories that need a toolchain change to stale evidence declare the file that pins it as a resource:

```text
Package.resolved
.swift-version
poetry.lock
```

---

## 71. When fingerprints are taken

The core fingerprints the live project. There is no frozen copy (chapter 13).

```text
use-cases verify --start    fingerprint every route: the start point (start.json, chapter 12)
use-cases verify --finish   fingerprint again: the finish point
use-cases verify --run      both, around the commands it runs

    fingerprint changed between the two?  -> no verdict: "code changed during the run"
    otherwise                              -> the verdict is stored with the start-point fingerprint

use-cases record              fingerprint now
```

A stored result carries the fingerprint of the state it was judged against. It may be stale against a newer live state immediately afterwards; that is correct.

---

## 72. Content-addressed reuse

The core MAY reuse previously calculated component fingerprints when validity can be proven.

Examples:

```text
same physical file
same content state
same normalization policy
```

may reuse the same content digest.

Caching is an optimization only.

An uncertain cache entry MUST be recomputed.

---

## 73. Shared implementation hashing

Implementation links are shared across every route in a use case.

Their content fingerprints SHOULD be calculated once per Workspace Model revision (chapter 09) and reused.

```text
implementation links
        |
hash once
        |
        +--> route A
        +--> route B
        +--> route C
```

---

## 74. Shared resource hashing

If multiple routes/resources require the same file (workspace path) under the same normalization policy, its whole-file content digest SHOULD be reused.

The file itself should not be redundantly read and hashed for every route.

---

## 75. Streaming

Large whole-file resources and manual whole-file bindings SHOULD be hashed incrementally.

The core does not need to load the entire file into memory merely to fingerprint it.

Normalization that requires text transformation MAY use streaming transformation where implementation permits.

---

## 76. Parallelism

Independent content hashing MAY occur in parallel.

Concurrency must not affect:

- content digests
- canonical collection ordering
- route fingerprints
- diagnostics

Final structured route input is always deterministically ordered before route hashing.

---

## 77. Component fingerprints

Implementations MAY internally maintain fingerprints for reusable components such as:

```text
link content
resource file
resolved scenario
procedure
implementation link set
```

These are performance details.

Only specified public fingerprint semantics are authoritative.

Changing an internal component representation MUST NOT change public route fingerprints.

Chapter 15 uses component fingerprints to explain which input made a route stale.

---

## 78. Incremental recomputation

A core implementation SHOULD be able to determine the minimal route fingerprint fan-out.

Examples:

```text
title changed
    -> zero routes

scenario A changed
    -> routes covering A

implementation link changed
    -> all routes in use case

route resource changed
    -> that route

intent changed
    -> all routes in use case
```

This enables large repositories to remain fast.

---

## 79. Deterministic ordering summary

Before structured route hashing:

```text
covered scenarios
    -> sort by scenario ID

implementation links
    -> group and sort by binding ID

validation links
    -> group and sort by binding ID

content-mode regions
    -> sort by normalized content identity, preserve duplicates

strict regions
    -> sort by canonical locator

resources
    -> sort by canonical workspace-relative path

mapping keys
    -> canonical structured encoding order
```

Filesystem enumeration order never participates.

---

## 80. Freshness transition examples

### Implementation changed

```text
verified
   |
implementation fingerprint changes
   |
   v
stale
```

### Route has never run

```text
READY
  |
no historical result
  |
  v
unverified
```

### Route reruns successfully

```text
stale
  |
PASS for current fingerprint
  |
  v
verified
```

### Exact old state restored

```text
state A PASS
   |
state B
   |
state A restored
   |
matching historical A PASS
   |
   v
verified
```

---

## 81. IDs and freshness summary

```text
use-case ID rename
    -> new use-case identity
    -> previous results do not transfer

route ID rename
    -> new route identity
    -> previous results do not transfer

scenario ID rename
    -> covered scenario fingerprint changes

binding ID rename
    -> link fingerprint changes

validation ID rename in use-cases-bridge.yml
    -> no change
```

---

## 82. Authoring movement summary

Under default `binding_identity: content`:

```text
definition YAML moved
    -> no route freshness change

marked region moved, or moved to another file
    -> no change if binding ID + content unchanged

manual binding file moved and locator updated
    -> no change if binding ID + content unchanged

marker replaced by a manual binding to the same content
    -> no change

resource file moved
    -> stale
```

Under:

```text
content-and-locator
```

link movement and source changes also stale affected routes.

---

## 83. Failure to fingerprint

If required fingerprint material cannot be safely resolved, the core MUST NOT invent a fingerprint.

Examples:

```text
resource disappears
manual binding locator invalid
file becomes unreadable
unsupported text required for marker resolution
link transformer fails
```

The authored/runtime state rules determine the resulting diagnostic/state.

A fabricated or partial fingerprint must never be used to claim freshness.

---

## 84. Non-goals

Fingerprinting does not:

- run validation
- prove tests are sufficient
- detect undeclared dependencies
- infer toolchain semantics
- hash the whole operating system
- parse programming languages
- normalize comments
- inspect Git history
- use commit hashes as freshness identity
- use timestamps as freshness identity
- use file modification time as semantic freshness identity

Filesystem metadata may be used to safely accelerate hashing, but never as the authoritative semantic fingerprint.

No part of the core reads modification times or report times to decide anything. Chapter 13's guard compares fingerprints.

---

## 85. Reference route fingerprint algorithm

Conceptually:

```text
1. ensure use case / route are safely resolvable

2. resolve repository freshness policy

3. collect covered scenarios
   -> canonicalize
   -> sort by scenario ID

4. canonicalize the route definition
   -> type, covers, gates_verification, procedure

5. resolve implementation links
   -> markers, manual bindings, link transformer links
   -> extract content
   -> normalize content
   -> fingerprint content
   -> apply binding identity policy
   -> group and sort by binding ID

6. resolve route validation links
   -> same process

7. resolve route resources
   -> expand globs
   -> canonicalize paths
   -> deduplicate
   -> normalize contents
   -> fingerprint contents
   -> sort by path

8. construct canonical RouteFingerprintInput

9. canonical serialize

10. hash using route-v1 SHA-256 domain

11. return:
    uc-route-v1-sha256:<digest>
```

---

## 86. Reference freshness algorithm

For a READY route:

```text
current = computeRouteFingerprint(route)

history = results for:
  use-case ID
  route ID

matching = history where:
  fingerprint format compatible
  fingerprint == current

if matching exists:
    result = latest matching result

    PASS       -> verified
    FAIL       -> failed
    INCOMPLETE -> incomplete
    ERROR      -> error

else if history exists:
    stale

else:
    unverified
```

---

## 87. Performance contract

Fingerprinting should approach the cost of reading only content that may actually affect the requested routes.

Preferred optimizations:

- reuse consistent canonical model revision data
- cache validated content hashes
- hash files once per relevant state
- share implementation hashes across routes
- expand each resource glob once per model revision
- stream large files
- hash independent content concurrently
- recompute only affected route payloads
- never reopen YAML merely to fingerprint canonical semantics

But:

```text
optimization makes freshness uncertain?
        |
       yes
        |
        v
recompute
```

Correctness always wins.

---

## 88. Final model

```text
                   Use Case
                      |
          +-----------+-----------+
          |                       |
       intent               implementation
          |                     links
          |                       |
          +-----------+-----------+
                      |
                Validation Route
                      |
         +------------+-------------+
         |            |             |
     scenarios    definition    resources
                 + procedure
         |            |             |
         +------------+-------------+
                      |
               validation links
                      |
                      v
            canonical route state
                      |
                      v
               route fingerprint
                      |
                      v
               result history
                      |
               +------+------+
               |             |
            matching      different
               |             |
               v             v
        result applicable   stale
```

Freshness is therefore a deterministic comparison between the exact validation state represented by a result and the current declared validation state.

---

## 89. Normative V1 fingerprint encoding

This section is normative. Earlier conceptual diagrams describe the same inputs but do not permit alternative wire representations.

### 89.1 Values and canonical JSON

Allowed values are null, booleans, strings, arrays, objects, and integers in the inclusive range -(2^53 - 1) through 2^53 - 1. Reject duplicate object keys, non-integers, and strings containing unpaired surrogates.

Canonical JSON has these exact rules:

- Encode as UTF-8 without a BOM or trailing newline.
- Order object keys by unsigned lexicographic comparison of their UTF-8 bytes.
- Write no whitespace outside strings.
- Write null, true, and false in lowercase.
- Write integers as base-10 ASCII with no leading zeros or plus sign; zero is `0`.
- Escape quotation mark as the two ASCII bytes 0x5c 0x22, and backslash as 0x5c 0x5c.
- Escape every U+0000 through U+001F as six ASCII bytes: backslash, lowercase u, and four lowercase hexadecimal digits (0000 through 001f). Do not use short escapes.
- Emit all other Unicode scalar values directly, including slash and non-ASCII characters. Perform no Unicode normalization.
- Preserve array order except for the explicitly sorted collections below.

Whenever this chapter says string sort, use that same unsigned UTF-8 byte ordering. Integers used as tie-breakers sort numerically.

### 89.2 Hash framing

For each fingerprint, let B be the payload bytes. Hash exactly:

```text
UTF8(domain) || 0x00 || ASCII(decimal byte length of B) || ASCII(":") || B
```

The decimal length has no leading zeros except zero itself.

Exact domains are:

```text
use-cases/content/v1
use-cases/route/v1
use-cases/workspace/v1
use-cases/promise/v1
```

Content payload B is the exact content after chapter 11 normalization. Route, workspace and promise payload B is canonical JSON defined here. SHA-256 digests are 64 lowercase hexadecimal characters. External prefixes are those in section 4.

Attachment blob hashing in chapter 12 is SHA-256 of exact bytes with no domain framing; it is a different identity system.

### 89.3 Content references

A content reference has exactly:

```json
{"algorithm":"sha256","byte_length":0,"digest":"<64 lowercase hexadecimal characters>"}
```

The digest is the domain-framed content hash. byte_length counts normalized payload bytes, not framing bytes.

An optional UTF-8 BOM is retained as U+FEFF when applying text normalization; neither supported normalization removes it. Exact mode always retains the original bytes.

### 89.4 Route payload

A route payload contains exactly these members:

```text
fingerprint_version: 1
freshness_policy: {
  binding_identity: "content" | "content-and-locator",
  normalization: { ignore: [...] }
}
use_case_id: fully resolved ID
route_id: local route ID
intent: exact canonical string
covered_scenarios: [...]
route: {
  type: {...},
  covers: [...],
  gates_verification: boolean,
  procedure: {...} | null
}
implementation_links: [...]
validation_links: [...]
resources: [...]
```

All listed members are required. Empty collections are represented explicitly; a route with no links has empty link arrays. No provenance, helper settings, result data, or extra fields enter the payload.

normalization.ignore is deduplicated and ordered line-endings before whitespace. covers is a deduplicated string-sorted list of scenario IDs. covered_scenarios is sorted by scenario ID and contains exactly id, given, when, and then; missing optional given becomes an empty array. Step-list order and exact strings are preserved.

A built-in type has exactly kind. A custom type has exactly kind = custom and name.

procedure is null when the route has none. Otherwise it has exactly setup, steps, and reset; optional omitted lists become []. All three list orders are preserved.

Paths use the loader's canonical workspace-relative spelling with "/" separators and root ".".

### 89.5 Link payloads

Link arrays contain one entry per binding ID in the collection and are sorted by binding ID.

In content mode, each entry has exactly:

```text
{ id, regions: [ ContentReference, ... ] }
```

Regions sort by digest string, then numeric byte_length, then algorithm string, preserving duplicates. A manual whole-file or range binding contributes one region. Each marker region and each link-transformer link contributes one region. An empty valid region contributes the empty-content reference, not an absent region.

In content-and-locator mode each entry has exactly:

```text
{ id, kind, regions: [ { locator, content }, ... ] }
```

kind is marker, manual, or transformer. content is the content reference. Each locator has exactly file, start_byte, and end_byte. file is the canonical workspace-relative path; byte offsets are zero-based offsets into the original file, with an exclusive end. Whole-file locators use zero and original byte length. Empty ranges have equal offsets.

Manual authored inclusive line/column positions, link-transformer line ranges, and marker-extracted regions are converted to these offsets before normalization. Marker sentinels are excluded from the selected range. For this conversion text is strict UTF-8; a column counts Unicode scalar values, not UTF-16 units or grapheme clusters. CRLF is one line boundary, as are lone CR and LF. An omitted start column means the beginning of that line; an omitted end column includes the entire ending line and its terminating line-break bytes if present. Explicit end columns include that scalar's bytes. Existing invalid/out-of-file position rules still apply.

Regions sort by file, then numeric start_byte, then numeric end_byte; content digest is the final tie-breaker. Keep duplicate contributions.

### 89.6 Resources

Each resource has exactly file and content. file is its canonical workspace-relative path; content is its content reference. Deduplicate by workspace path as specified earlier, then sort by file.

A file's identity is its workspace path (§42), so a hard link is a separate file and no representative is chosen among paths.

### 89.7 Workspace payload

The workspace payload has exactly:

```text
fingerprint_version: 1
scopes: [...]
use_cases: [...]
groups: {...}
```

It projects the canonical authored/resolved model revision, not linked file bytes:

- scopes sorts by canonical workspace-relative scope directory. Each item has exactly path, parent (null for root), namespace (fully composed namespace or empty string), schema_version, use_cases_dir (canonical scope-relative path), configuration.
- configuration contains the scope's effective schema-defined configuration, excluding schema_version, prefix, and use_cases_dir already represented above. Root-only freshness and discovery appear at the root only, and a child scope's configuration is {}. Absent root discovery becomes {exclude: []}; freshness defaults are explicit. discovery.exclude is deduplicated and sorted.
- use_cases sorts by fully resolved ID. Each item is the canonical use-case object defined in chapter 02, with id replaced by that full ID, plus scope containing the owning scope path. Definition-file location and file prefix are omitted after ID resolution. Scenarios, validation routes, and manual bindings sort by their local IDs; covers sorts as a set. Behavioral step arrays, procedure lists, and out_of_scope preserve order.
- In DRAFT objects, absent optional scalar members are omitted rather than converted to null. Optional collection fields become their empty collection values. Route fields use their defined defaults even in DRAFT; an absent procedure remains absent. No INVALID object receives a workspace fingerprint.
- Manual bindings in this workspace projection retain kind and canonical authored locator fields, not extracted regions or file digests. Markers and link-transformer links never appear. Resource declarations retain canonical authored selector objects, deduplicated and sorted by their canonical JSON bytes. This describes authored semantics without reading external content into the workspace fingerprint.
- groups is keyed by resolved group name. Each value has exactly description (omitted if absent) and members (deduplicated, sorted fully resolved use-case IDs). Membership is resolved before projection. Equivalent selectors producing the same membership and description produce the same group projection.

All schema-defined human metadata remains in the workspace projection unless explicitly excluded above. Warnings, diagnostics, source provenance, absolute workspace location, runtime status, and evidence never appear. A future new semantic field requires an explicit projection rule and a fingerprint-version review.

### 89.8 Conformance vectors

These vectors fix the encoding and framing boundaries. Hash vectors use exact UTF-8 payload bytes with no trailing newline. `docs/schemas/engine/fingerprint_vectors.py` reproduces every value below, and `validate.py` checks that this chapter and that script agree.

Canonical string-escaping probe, with a newline, quotation mark, and backslash in z:

```json
{"a":"é","z":"\u000a\"\\"}
```

| Domain kind | Payload bytes | SHA-256 digest |
|---|---|---|
| content | empty, length 0 | e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5 |
| content | ASCII abc, length 3 | efb223658e20ee620f5c7f42edb1f1146cda800481df6206f80e86ac400dd989 |
| content | ASCII {}, length 2 | 52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8 |
| workspace | ASCII {}, length 2 | 9b1a9c046021c571b4e67572309c0bcdcb37fa3778a8143105ea2b5a7d49d7e7 |

The workspace {} vector tests framing only; {} is not a valid complete workspace payload.

**Vector A — a procedural route with no links**, exactly 552 bytes:

```json
{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"when":["Perform the action."]}],"fingerprint_version":1,"freshness_policy":{"binding_identity":"content","normalization":{"ignore":["line-endings"]}},"implementation_links":[],"intent":"Demonstrate success.","resources":[],"route":{"covers":["success"],"gates_verification":true,"procedure":{"reset":[],"setup":[],"steps":["Perform the action and observe success."]},"type":{"kind":"acceptance"}},"route_id":"manual","use_case_id":"example.success","validation_links":[]}
```

```text
uc-route-v1-sha256:e909a34e46f252338a7cfee137a5bb0d40ed94f67ba7b85f507ce1af4804e581
```

**Vector B — an automated route in content mode**, with one empty implementation link, one validation link whose region is `abc` and its line break, and one resource containing `{}`; exactly 927 bytes:

```json
{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"when":["Perform the action."]}],"fingerprint_version":1,"freshness_policy":{"binding_identity":"content","normalization":{"ignore":["line-endings"]}},"implementation_links":[{"id":"implementation","regions":[{"algorithm":"sha256","byte_length":0,"digest":"e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5"}]}],"intent":"Demonstrate success.","resources":[{"content":{"algorithm":"sha256","byte_length":2,"digest":"52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8"},"file":"fixtures/users.json"}],"route":{"covers":["success"],"gates_verification":true,"procedure":null,"type":{"kind":"unit"}},"route_id":"unit-tests","use_case_id":"example.success","validation_links":[{"id":"success","regions":[{"algorithm":"sha256","byte_length":4,"digest":"e325e71c1fee5ac429847c81d789073ceff87b488b359350282a774dd76ac849"}]}]}
```

```text
uc-route-v1-sha256:7701c45be50ad8d5014cc0b9a224cd78f61b2c3854d59d43473c8640d8b375ee
```

**Vector C — vector B's inputs under `content-and-locator`**: the implementation link is a whole-file manual binding of the empty file `src/app.swift` (bytes 0–0), and the validation link is the marker region at bytes 48–52 of `tests/app_tests.swift`, whose content is `// @use-case:example.success#unit-tests.success` LF `abc` LF `// @use-case:end example.success#unit-tests.success` LF; exactly 1131 bytes:

```json
{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"when":["Perform the action."]}],"fingerprint_version":1,"freshness_policy":{"binding_identity":"content-and-locator","normalization":{"ignore":["line-endings"]}},"implementation_links":[{"id":"implementation","kind":"manual","regions":[{"content":{"algorithm":"sha256","byte_length":0,"digest":"e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5"},"locator":{"end_byte":0,"file":"src/app.swift","start_byte":0}}]}],"intent":"Demonstrate success.","resources":[{"content":{"algorithm":"sha256","byte_length":2,"digest":"52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8"},"file":"fixtures/users.json"}],"route":{"covers":["success"],"gates_verification":true,"procedure":null,"type":{"kind":"unit"}},"route_id":"unit-tests","use_case_id":"example.success","validation_links":[{"id":"success","kind":"marker","regions":[{"content":{"algorithm":"sha256","byte_length":4,"digest":"e325e71c1fee5ac429847c81d789073ceff87b488b359350282a774dd76ac849"},"locator":{"end_byte":52,"file":"tests/app_tests.swift","start_byte":48}}]}]}
```

```text
uc-route-v1-sha256:29a534caec5762a5f3e010c19c0bb0525cb16c1ec9f35da2f9117367705e7011
```

**Vector D — same-line mode with a nested pair**: vector B, except that the validation file `tests/app_tests.swift` is the single line `x = /* @use-case:example.success#unit-tests.success */ f() + /* @use-case:example.other#inner */ g() /* @use-case:end example.other#inner */ /* @use-case:end example.success#unit-tests.success */` and LF. The region is the bytes between the outer tokens less each nested token, so its content is ` */ f() + /*  */ g() /*  */ /* `; exactly 928 bytes:

```json
{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"when":["Perform the action."]}],"fingerprint_version":1,"freshness_policy":{"binding_identity":"content","normalization":{"ignore":["line-endings"]}},"implementation_links":[{"id":"implementation","regions":[{"algorithm":"sha256","byte_length":0,"digest":"e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5"}]}],"intent":"Demonstrate success.","resources":[{"content":{"algorithm":"sha256","byte_length":2,"digest":"52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8"},"file":"fixtures/users.json"}],"route":{"covers":["success"],"gates_verification":true,"procedure":null,"type":{"kind":"unit"}},"route_id":"unit-tests","use_case_id":"example.success","validation_links":[{"id":"success","regions":[{"algorithm":"sha256","byte_length":31,"digest":"305c89298d281a6dd3feecc816b5e4f98347b1c96e1ea781db6f7338cbe31294"}]}]}
```

```text
uc-route-v1-sha256:1a251529ca94a1cd5649a8a594023287e1f97aa22729f68fccb152936340cdb3
```

**Vector E — line mode with nested sentinel lines, under `content-and-locator`**: vector C, except that `tests/app_tests.swift` holds the outer start sentinel line, `abc`, a nested pair's start line, `def`, the nested end line and the outer end line, each ending LF. The locator spans the whole region, bytes 48–126, while the content leaves out the nested sentinel lines and is `abc` LF `def` LF; exactly 1132 bytes:

```json
{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"when":["Perform the action."]}],"fingerprint_version":1,"freshness_policy":{"binding_identity":"content-and-locator","normalization":{"ignore":["line-endings"]}},"implementation_links":[{"id":"implementation","kind":"manual","regions":[{"content":{"algorithm":"sha256","byte_length":0,"digest":"e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5"},"locator":{"end_byte":0,"file":"src/app.swift","start_byte":0}}]}],"intent":"Demonstrate success.","resources":[{"content":{"algorithm":"sha256","byte_length":2,"digest":"52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8"},"file":"fixtures/users.json"}],"route":{"covers":["success"],"gates_verification":true,"procedure":null,"type":{"kind":"unit"}},"route_id":"unit-tests","use_case_id":"example.success","validation_links":[{"id":"success","kind":"marker","regions":[{"content":{"algorithm":"sha256","byte_length":8,"digest":"52d0f4b311a9e006bde69e359deb00f6291a10e1bfbf23c18a1c93613984c491"},"locator":{"end_byte":126,"file":"tests/app_tests.swift","start_byte":48}}]}]}
```

```text
uc-route-v1-sha256:af91ac81aba75c48283b27ee159ca8776bb44ada1901592c555eb7f366f2d632
```

B and C differ only in freshness policy and locators, so the pair shows that changing `binding_identity` changes every fingerprint (section 45). Every vector uses the default normalization, which ignores line endings, so an LF and a CRLF checkout of the same code agree.

Implementations must also establish that object insertion order does not change these bytes, that duplicate content regions remain significant, and that no helper setting (command, transformer, report name) can enter the payload.

### 89.9 Promise payload

The fingerprint of a use case's promise (`approved.behaviour`, chapters 02 and 21) is computed like the others: canonical JSON (§89.1) of the payload below, framed with the domain `use-cases/promise/v1` (§89.2), SHA-256. It is written as the 64 lowercase hexadecimal characters of the digest, with no prefix.

The payload contains exactly these members:

```text
id: the use case's fully resolved ID
title
description
value_tier
intent
scenarios: [ { id, given, when, then }, ... ]
out_of_scope: [...]
```

Every member is written. Absent text (`description`, `value_tier`, `intent`) is null. Absent lists (`scenarios`, `out_of_scope`, and a scenario's `given`) are `[]`. Scenarios, step lists and `out_of_scope` keep their authored order and exact strings.

Nothing else enters: no route, binding, resource, scope or approval record. Changing how a use case is proven keeps its promise fingerprint.
