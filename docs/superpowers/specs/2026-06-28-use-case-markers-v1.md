# Use-Case Markers + Guard - v1 implementation spec

Status: IR-approved (independent review, deepest mode), 4 amendments folded in.
Date: 2026-06-28. Agents follow this verbatim through the phased build.

---

# A. Decision

Approved, with four amendments I would not skip.

## Amendment 1: `//:` is not universal

If the watched product is Swift-only or uses `//` comments, fine.

If the watched product is truly "any language", the literal marker cannot always be `//:` because it is invalid syntax in Python, Ruby, shell, YAML, SQL, etc.

Use this semantic marker:

```txt
<configured-line-comment-prefix>: @use-case: <slug>
```

For Swift, this remains exactly:

```swift
//: @use-case: checkout.apply_coupon
```

This keeps the marker identity-only. It only prevents breaking non-`//` languages.

## Amendment 2: the binding registry must be append-only too

"Marker removal = suspect" only works if the memory that a row had a binding cannot be silently deleted.

So the row-to-binding registry must be an append-only JSONL log, validated like the evidence ledger. A mutable registry JSON file is a bypass hole.

## Amendment 3: trusted proof needs mechanical provenance

"Only trusted CI can mint proof events" is not true if an agent can just commit a JSONL line that looks like a proof.

Proof events need one of these:

```txt
- CI-owned external evidence store, or
- signed proof events
```

For v1, I would use signed proof events. The public verification key is in the repo/config. The private signing key exists only in trusted CI.

Without this, the agent can manufacture green.

## Amendment 4: inferred Swift marker placement must be strict

For inferred Swift functions, the marker must sit immediately before the whole attached declaration group.

Good:

```swift
//: @use-case: checkout.apply_coupon
@MainActor
@available(iOS 17, *)
public func applyCoupon(...) async throws -> Result {
    ...
}
```

Bad:

```swift
@MainActor
//: @use-case: checkout.apply_coupon
public func applyCoupon(...) async throws -> Result {
    ...
}
```

The bad version must be invalid, because otherwise the marker can miss behavior-bearing attributes.

With those amendments, v1 is sound and buildable.

The core is right:

```txt
comments bind
registry remembers
ledger proves
freshness is derived
CI is authority
```

# B. V1 implementation spec

## 0. Non-negotiable rules

These are invariants, not preferences.

```txt
1. A source marker contains identity only.
2. A marker never contains row hash, span hash, status, role, tier, proof, or freshness.
3. Freshness is computed, never stored.
4. A binding registry remembers every registered binding slug append-only.
5. A proof event is valid only if minted by trusted CI.
6. Scan can report suspect, but cannot prove.
7. Bind can place/register markers, but cannot prove.
8. Prove recomputes all hashes itself and appends evidence only on passing verification.
9. Unsupported inference is invalid, not best-effort.
10. Explicit end works everywhere a configured line-comment prefix exists.
```

Recommended file layout:

```txt
.use-cases/
  proofs.jsonl
  bindings.jsonl
  trusted-ci-public-key.pem
  use-cases.config.json

usecases/
  checkout.yaml
```

Core constants:

```txt
MARKER_SCHEMA_ID = "ucase-marker-v1"
BINDING_REGISTRY_SCHEMA_ID = "ucase-binding-registry-event-v1"
EVIDENCE_SCHEMA_ID = "ucase-proof-event-v1"
STATUS_SCHEMA_ID = "ucase-freshness-status-v1"

SPAN_CANON_ID = "ucase-span-lines-v1"
EXPLICIT_RECOGNIZER_ID = "explicit-span-v1"
SWIFT_FUNC_RECOGNIZER_ID = "swift-func-inferred-v1"
BINDING_SET_HASH_ID = "ucase-binding-set-v1"
ROW_HASH_ID = existing semantic row hash algorithm
```

---

# 1. Marker grammar

## 1.1 Semantic marker

The semantic marker is:

```txt
<line-comment-prefix>: @use-case: <payload>
```

For Swift:

```swift
//: @use-case: checkout.apply_coupon
```

For Python, if enabled by config:

```python
#: @use-case: checkout.apply_coupon
```

For YAML, if enabled by config:

```yaml
#: @use-case: checkout.apply_coupon
```

If you do not want comment-prefix abstraction in v1, then explicitly document:

```txt
v1 only supports files whose configured marker prefix is "//".
```

Do not pretend it supports every language.

## 1.2 EBNF-ish grammar

```txt
marker-line        = wsp? comment-prefix ": @use-case:" wsp marker-payload wsp? line-end

comment-prefix     = configured line comment prefix for file extension
                   | "//" for Swift

marker-payload     = start-payload
                   | end-payload

start-payload      = slug

end-payload        = "end" wsp slug

slug               = row-id [ "#" binding-suffix ]

row-id             = ident { "." ident }

binding-suffix     = suffix-ident { "." suffix-ident }

ident              = lower-alpha { lower-alpha | digit | "_" }

suffix-ident       = lower-alpha { lower-alpha | digit | "_" | "-" }

lower-alpha        = "a".."z"

digit              = "0".."9"

wsp                = " " | "\t"
```

Valid:

```txt
//: @use-case: checkout.apply_coupon
//: @use-case: checkout.apply_coupon#handler
//: @use-case: checkout.apply_coupon#tax
//: @use-case: end checkout.apply_coupon#tax
```

Invalid:

```txt
//: @use-case: checkout.apply_coupon fresh=true
//: @use-case: checkout.apply_coupon sha256=abc
//: @use-case: checkout.apply_coupon role=impl
//: @use-case: checkout.apply_coupon#
//: @use-case: end
//: @use-case: end checkout.other_row
```

## 1.3 Slug rules

The full slug is the binding identity.

```txt
row id:      checkout.apply_coupon
binding id:  checkout.apply_coupon#tax
```

Rules:

```txt
1. The row id is the part before "#".
2. The full slug must be unique among start markers in the current repo.
3. The full slug must be registered in the append-only binding registry.
4. One row may have many bindings by suffix.
5. A start marker without suffix is allowed, but only once for that row.
6. End markers repeat the full slug and do not count as duplicate bindings.
7. Current marker slug not in registry = INVALID.
8. Registry slug pointing to missing row = INVALID in v1.
9. No row retirement flow in v1. Deleting a row with registered bindings is INVALID.
```

---

# 2. Span rules

There are two span modes.

## 2.1 Explicit span

Works for any file with a configured line-comment prefix.

```txt
<comment>: @use-case: checkout.apply_coupon#tax
... span body ...
<comment>: @use-case: end checkout.apply_coupon#tax
```

The span body is:

```txt
all complete lines strictly between the start marker line and matching end marker line
```

The hash excludes both marker lines.

Rules:

```txt
1. End slug must exactly match start slug.
2. Nested spans are invalid in v1.
3. Overlapping spans are invalid in v1.
4. End without start is invalid.
5. Start without end is invalid unless Swift function inference succeeds.
6. Explicit span wins over inference.
```

## 2.2 Inferred Swift function span

Only supported for Swift `func` declarations.

Example:

```swift
//: @use-case: checkout.apply_coupon
@MainActor
@available(iOS 17, *)
public func applyCoupon<T>(_ code: String, cart: T) async throws -> CouponResult
    where T: CartLike {
    ...
}
```

The computed span starts at the first attached declaration token:

```txt
@MainActor
```

or, if there are no attributes:

```txt
public
```

or, if there are no modifiers:

```txt
func
```

The computed span ends at the closing brace of the function body.

The marker line itself is excluded from the span hash.

---

# 3. Span canonicalization

Use one canonicalizer in v1:

```txt
ucase-span-lines-v1
```

Algorithm:

```txt
Input: source file bytes and computed span line range.

1. Require UTF-8.
2. Decode as UTF-8.
3. Normalize CRLF and CR to LF.
4. Select complete lines in the span range.
5. Exclude marker lines.
6. Strip trailing spaces and tabs from each selected line.
7. Preserve leading whitespace.
8. Preserve comments.
9. Preserve blank lines.
10. Join with LF.
11. Ensure exactly one trailing LF.
12. sha256 over UTF-8 bytes.
```

Reasoning:

```txt
- False positives are acceptable.
- False negatives are poison.
- Do not ignore comments yet; language-specific semantic hashing is out of scope.
- Do not AST-hash yet.
```

---

# 4. Binding registry

## 4.1 File

```txt
.use-cases/bindings.jsonl
```

This is append-only.

It records that a binding slug is known to belong to a row. It does not prove anything.

## 4.2 Registry event schema

Each line is one JSON object:

```json
{
  "schema": "ucase-binding-registry-event-v1",
  "event_type": "binding_registered",
  "event_id": "01JABCDEF00000000000000000",
  "created_at": "2026-06-28T12:00:00Z",
  "created_by": {
    "tool": "use-case-matrix",
    "command": "bind",
    "version": "0.1.0"
  },
  "row_id": "checkout.apply_coupon",
  "binding_slug": "checkout.apply_coupon#handler",
  "reason": "initial_bind"
}
```

## 4.3 Registry validation

The materialized registry is built by reading the JSONL in order.

Validation rules:

```txt
1. Every line must parse as JSON.
2. Every event must match schema.
3. event_type must be "binding_registered".
4. binding_slug row prefix must equal row_id.
5. row_id must exist in YAML rows.
6. A binding_slug may be registered once.
7. Re-registering the same binding_slug to the same row is allowed only if event_id differs and command uses reason "idempotent_register"; otherwise reject for v1 simplicity.
8. Registering same binding_slug to a different row is INVALID.
9. Existing registry lines may not be edited or deleted.
10. New lines may only be appended.
```

Recommended v1 simplification:

```txt
Do not allow duplicate registration at all.
```

That is easier.

## 4.4 Current binding record

Produced by `scan`, not committed as truth.

```json
{
  "binding_slug": "checkout.apply_coupon#handler",
  "row_id": "checkout.apply_coupon",
  "suffix": "handler",
  "file_path": "Sources/Checkout/CouponService.swift",
  "comment_prefix": "//",
  "extent_kind": "swift_func_inferred",
  "recognizer_id": "swift-func-inferred-v1",
  "span_canon_id": "ucase-span-lines-v1",
  "start_marker": {
    "line": 12,
    "column": 1
  },
  "end_marker": null,
  "span": {
    "start_line": 13,
    "end_line": 27,
    "start_byte": 355,
    "end_byte": 849,
    "sha256": "sha256:..."
  },
  "diagnostic": {
    "symbol_kind": "swift_func",
    "symbol_name": "applyCoupon",
    "inferred": true
  }
}
```

For explicit spans:

```json
{
  "binding_slug": "checkout.apply_coupon#tax",
  "row_id": "checkout.apply_coupon",
  "suffix": "tax",
  "file_path": "Sources/Checkout/CouponRules.swift",
  "comment_prefix": "//",
  "extent_kind": "explicit",
  "recognizer_id": "explicit-span-v1",
  "span_canon_id": "ucase-span-lines-v1",
  "start_marker": {
    "line": 44,
    "column": 1
  },
  "end_marker": {
    "line": 61,
    "column": 1
  },
  "span": {
    "start_line": 45,
    "end_line": 60,
    "start_byte": 1200,
    "end_byte": 1690,
    "sha256": "sha256:..."
  },
  "diagnostic": {
    "inferred": false
  }
}
```

## 4.5 Binding set hash

The current binding set for a row is hashed from current scan output.

Canonical material:

```json
{
  "schema": "ucase-binding-set-v1",
  "row_id": "checkout.apply_coupon",
  "bindings": [
    {
      "binding_slug": "checkout.apply_coupon#handler",
      "row_id": "checkout.apply_coupon",
      "file_path": "Sources/Checkout/CouponService.swift",
      "extent_kind": "swift_func_inferred",
      "recognizer_id": "swift-func-inferred-v1",
      "span_canon_id": "ucase-span-lines-v1",
      "span_sha256": "sha256:..."
    },
    {
      "binding_slug": "checkout.apply_coupon#tax",
      "row_id": "checkout.apply_coupon",
      "file_path": "Sources/Checkout/CouponRules.swift",
      "extent_kind": "explicit",
      "recognizer_id": "explicit-span-v1",
      "span_canon_id": "ucase-span-lines-v1",
      "span_sha256": "sha256:..."
    }
  ]
}
```

Rules:

```txt
1. Sort bindings by binding_slug before hashing.
2. Include file_path.
3. Include extent_kind.
4. Include recognizer_id.
5. Include span_canon_id.
6. Include span_sha256.
7. Do not include line numbers in the hash.
8. Do not include timestamps.
9. Do not include proof status.
10. Do not include marker text.
```

Line numbers remain diagnostics only.

This avoids making every unrelated line insertion above a function stale. The tradeoff is that same-text movement within the same file may not stale. That is accepted v1 false locality.

Hash:

```txt
binding_set_hash = sha256(canonical_json(binding_set_material))
```

---

# 5. Evidence event schema

## 5.1 File

```txt
.use-cases/proofs.jsonl
```

Append-only.

Only trusted CI may append proof events.

## 5.2 Proof event

Each passing proof appends one line:

```json
{
  "schema": "ucase-proof-event-v1",
  "event_type": "row_proof_passed",
  "event_id": "01JABCDEFAAAAAAAAAAAAAAAAAA",
  "created_at": "2026-06-28T12:05:00Z",
  "producer": {
    "kind": "trusted-ci-prover",
    "id": "github-actions/use-cases-prover",
    "version": "0.1.0",
    "ci_run_id": "123456789",
    "repo": "org/product",
    "commit": "0123456789abcdef0123456789abcdef01234567"
  },
  "row": {
    "row_id": "checkout.apply_coupon",
    "row_hash_id": "existing-semantic-row-hash",
    "row_hash": "sha256:...",
    "verification_policy_hash": "sha256:...",
    "approval_policy_hash": "sha256:..."
  },
  "bindings": {
    "binding_set_hash_id": "ucase-binding-set-v1",
    "binding_set_hash": "sha256:...",
    "span_canon_id": "ucase-span-lines-v1",
    "items": [
      {
        "binding_slug": "checkout.apply_coupon#handler",
        "row_id": "checkout.apply_coupon",
        "file_path": "Sources/Checkout/CouponService.swift",
        "extent_kind": "swift_func_inferred",
        "recognizer_id": "swift-func-inferred-v1",
        "span_canon_id": "ucase-span-lines-v1",
        "span_sha256": "sha256:...",
        "span_start_line": 13,
        "span_end_line": 27
      }
    ]
  },
  "verification": {
    "command_id": "acceptance.checkout.apply_coupon",
    "result": "pass",
    "started_at": "2026-06-28T12:04:10Z",
    "completed_at": "2026-06-28T12:04:59Z",
    "artifacts": [
      {
        "kind": "junit",
        "path": "artifacts/use-cases/checkout.apply_coupon/junit.xml",
        "sha256": "sha256:..."
      }
    ]
  },
  "signature": {
    "alg": "ed25519",
    "key_id": "trusted-ci-2026-01",
    "value": "base64..."
  }
}
```

## 5.3 Signature rule

Canonical signing payload:

```txt
canonical_json(event without signature)
```

Validation:

```txt
ed25519_verify(public_key_for_key_id, canonical_payload, signature.value)
```

Rules:

```txt
1. Unsigned proof event = INVALID.
2. Unknown key_id = INVALID.
3. Bad signature = INVALID.
4. producer.kind must be "trusted-ci-prover".
5. verification.result must be "pass".
6. prove must never append failed proof events.
7. Agents may not generate trusted signatures.
```

## 5.4 Evidence hash recomputation

`validate-ledger` must recompute:

```txt
1. event canonical payload hash
2. binding_set_hash from event.bindings.items
3. artifact hashes if artifact files are present and configured as required
4. signature over canonical payload
```

Important distinction:

```txt
Current code span changed since proof event = SUSPECT, not INVALID.

Proof event internally inconsistent = INVALID.
```

So this is invalid:

```txt
event.bindings.binding_set_hash does not equal hash(event.bindings.items)
```

But this is only suspect:

```txt
event.bindings.items[0].span_sha256 != current scanned span sha256
```

---

# 6. Freshness status object

`scan` emits this object.

```json
{
  "schema": "ucase-freshness-status-v1",
  "generated_at": "2026-06-28T12:10:00Z",
  "tool": {
    "name": "use-case-matrix",
    "version": "0.1.0"
  },
  "product_root": "/workspace/product",
  "policy_mode": "feature",
  "guard_ok": true,
  "summary": {
    "fresh": 1,
    "suspect": 0,
    "unproven": 0,
    "unbound": 3,
    "invalid": 0,
    "policy_blocked": 0
  },
  "integrity_errors": [],
  "rows": [
    {
      "row_id": "checkout.apply_coupon",
      "row_hash": "sha256:...",
      "verification_policy_hash": "sha256:...",
      "approval_policy_hash": "sha256:...",
      "status": "FRESH",
      "policy_block": false,
      "reasons": [],
      "known_binding_slugs": [
        "checkout.apply_coupon#handler"
      ],
      "current_binding_slugs": [
        "checkout.apply_coupon#handler"
      ],
      "missing_registered_binding_slugs": [],
      "unregistered_current_binding_slugs": [],
      "current_binding_set_hash": "sha256:...",
      "current_bindings": [
        {
          "binding_slug": "checkout.apply_coupon#handler",
          "file_path": "Sources/Checkout/CouponService.swift",
          "extent_kind": "swift_func_inferred",
          "recognizer_id": "swift-func-inferred-v1",
          "span_canon_id": "ucase-span-lines-v1",
          "span_sha256": "sha256:...",
          "span_start_line": 13,
          "span_end_line": 27
        }
      ],
      "matching_proof_event": {
        "event_id": "01JABCDEFAAAAAAAAAAAAAAAAAA",
        "created_at": "2026-06-28T12:05:00Z",
        "commit": "0123456789abcdef0123456789abcdef01234567"
      },
      "latest_trusted_proof_event": {
        "event_id": "01JABCDEFAAAAAAAAAAAAAAAAAA",
        "created_at": "2026-06-28T12:05:00Z",
        "commit": "0123456789abcdef0123456789abcdef01234567"
      },
      "required_action": null
    }
  ]
}
```

Suspect example:

```json
{
  "row_id": "checkout.apply_coupon",
  "status": "SUSPECT",
  "policy_block": false,
  "reasons": [
    {
      "code": "CODE_SPAN_CHANGED",
      "binding_slug": "checkout.apply_coupon#handler",
      "expected_span_sha256": "sha256:old",
      "actual_span_sha256": "sha256:new"
    }
  ],
  "required_action": "use-cases prove --row checkout.apply_coupon"
}
```

---

# 7. State machine and predicates

Compute these inputs first:

```txt
R = all YAML rows
K(row) = registered binding slugs for row from bindings.jsonl
C(row) = current scanned, valid, registered binding records for row
P(row) = valid trusted passing proof events for row from proofs.jsonl
Hrow(row) = current semantic row hash
Hverify(row) = current verification policy hash
Happrove(row) = current approval policy hash
Hbind(row) = current binding_set_hash from C(row)
```

Also compute:

```txt
missing(row) = K(row) - current_binding_slugs(row)
unregistered(row) = current_marker_slugs(row) - registered_binding_slugs(row)
```

## 7.1 INVALID

A row is `INVALID` if any binding integrity error prevents safe reasoning for that row.

Examples:

```txt
malformed marker
forbidden marker payload
duplicate full slug
unregistered current marker slug
marker row id does not exist
registry row id does not exist
registry slug conflicts with row id
end marker without start
start/end slug mismatch
unclosed explicit span
unsupported inferred form
ambiguous Swift inferred form
nested/overlapping spans
ledger schema invalid
registry schema invalid
evidence signature invalid
evidence event internal hash mismatch
non-append ledger edit
non-append registry edit
```

Global integrity errors may mark all rows invalid depending on severity.

Predicate:

```txt
if integrity_errors_for_row(row).length > 0:
    status = INVALID
```

## 7.2 UNBOUND

A row is `UNBOUND` only if it has never had a registered binding and has no current binding.

Predicate:

```txt
if K(row) is empty and C(row) is empty:
    status = UNBOUND
```

Important:

```txt
A row with a registered binding that is now missing is not UNBOUND.
It is SUSPECT.
```

## 7.3 SUSPECT for removed bindings

Marker removal must not disappear.

Predicate:

```txt
if missing(row) is not empty:
    status = SUSPECT
    reason = BINDING_REMOVED
```

If all bindings are missing:

```txt
reason = ALL_BINDINGS_REMOVED
```

## 7.4 UNPROVEN

A row is `UNPROVEN` if it has current registered bindings, no missing registered bindings, and no trusted passing proof event exists for that row.

Predicate:

```txt
if C(row) is not empty
and missing(row) is empty
and P(row) is empty:
    status = UNPROVEN
```

This is the normal state after a new binding is added.

## 7.5 FRESH

A row is `FRESH` if at least one trusted passing proof event matches the current row and current binding set.

Predicate:

```txt
exists proof in P(row) such that:

proof.row.row_hash == Hrow(row)
and proof.row.verification_policy_hash == Hverify(row)
and proof.row.approval_policy_hash == Happrove(row)
and proof.bindings.binding_set_hash == Hbind(row)
and all proof binding items use supported span_canon_id
and current approval policy accepts proof.producer and proof.verification
```

Use the newest matching proof event for reporting.

Do not require proof commit to equal current commit. Commit is provenance, not freshness. Otherwise every commit would stale every row.

## 7.6 SUSPECT for stale proof

If none of the above applies, the row is `SUSPECT`.

Common reasons:

```txt
ROW_HASH_CHANGED
VERIFICATION_POLICY_CHANGED
APPROVAL_POLICY_CHANGED
BINDING_SET_CHANGED
CODE_SPAN_CHANGED
BINDING_ADDED
BINDING_REMOVED
BINDING_PATH_CHANGED
CANON_CHANGED
POLICY_NO_LONGER_APPLIES
NO_MATCHING_TRUSTED_PROOF
```

Reason derivation:

```txt
If latest proof row_hash != current row_hash:
    ROW_HASH_CHANGED

If latest proof verification_policy_hash != current:
    VERIFICATION_POLICY_CHANGED

If latest proof approval_policy_hash != current:
    APPROVAL_POLICY_CHANGED

For same binding_slug:
    if proof file_path != current file_path:
        BINDING_PATH_CHANGED
    if proof span_sha256 != current span_sha256:
        CODE_SPAN_CHANGED
    if proof span_canon_id != current span_canon_id:
        CANON_CHANGED

If current slugs contain slug not in latest proof:
    BINDING_ADDED

If latest proof contains slug not current:
    BINDING_REMOVED
```

---

# 8. Tool contracts

Use these exit codes across CLI commands:

```txt
0 = success, no blocking condition
1 = freshness policy block
2 = usage/config/internal error
3 = binding integrity failure
4 = ledger/registry validation failure
5 = verification failed
6 = untrusted proof append attempted
```

## 8.1 `bind`

Purpose:

```txt
Place/register a source marker.
Never prove anything.
```

Command shape:

```txt
use-cases bind \
  --row checkout.apply_coupon \
  --file Sources/Checkout/CouponService.swift \
  --line 12 \
  --mode swift-func
```

Explicit span:

```txt
use-cases bind \
  --row checkout.apply_coupon \
  --suffix tax \
  --file Sources/Checkout/CouponRules.swift \
  --start-line 44 \
  --end-line 60 \
  --mode explicit
```

Register an already placed valid marker:

```txt
use-cases bind \
  --row checkout.apply_coupon \
  --suffix handler \
  --file Sources/Checkout/CouponService.swift \
  --line 12 \
  --register-existing
```

Inputs:

```txt
--row <row_id>
--suffix <suffix> optional
--file <path>
--line <line> for inferred
--start-line <line> for explicit
--end-line <line> for explicit
--mode explicit | swift-func
--comment-prefix <prefix> optional
--registry <path> optional
--rows-root <path> optional
--product-root <path> optional
--dry-run optional
--json optional
```

Derived:

```txt
binding_slug = row_id if no suffix
binding_slug = row_id + "#" + suffix if suffix
```

Must do:

```txt
1. Verify row exists.
2. Verify binding_slug grammar.
3. Verify binding_slug not already registered unless --register-existing and exact same binding exists.
4. Insert marker using configured line-comment prefix.
5. For explicit mode, insert matching end marker with repeated slug.
6. For swift-func mode, insert marker immediately before the full attached Swift declaration group.
7. Run scanner on affected file.
8. Verify resulting marker is valid.
9. Append binding_registered event to bindings.jsonl.
10. Output JSON summary.
```

Must not do:

```txt
1. Must not write proofs.jsonl.
2. Must not emit proof events.
3. Must not write row freshness.
4. Must not accept caller-supplied span hash.
5. Must not accept caller-supplied row hash.
6. Must not silently create unsupported inferred markers.
```

Transactional rule:

```txt
Append registry event only after source edit validates.
If source edit validation fails, roll back source edit if possible and do not append registry event.
```

Output example:

```json
{
  "ok": true,
  "command": "bind",
  "row_id": "checkout.apply_coupon",
  "binding_slug": "checkout.apply_coupon#handler",
  "file_path": "Sources/Checkout/CouponService.swift",
  "mode": "swift-func",
  "registry_event_appended": true,
  "scan_result": {
    "extent_kind": "swift_func_inferred",
    "span_start_line": 13,
    "span_end_line": 27,
    "span_sha256": "sha256:..."
  }
}
```

Exit codes:

```txt
0 success
2 usage/config/internal error
3 binding integrity failure
4 registry validation failure
```

## 8.2 `scan`

Purpose:

```txt
Validate markers, compute spans, compute binding set hashes, derive row freshness.
Never mutate source, registry, or ledger.
```

Command:

```txt
use-cases scan \
  --product-root . \
  --rows-root usecases \
  --proofs .use-cases/proofs.jsonl \
  --bindings .use-cases/bindings.jsonl \
  --policy-mode feature \
  --json
```

Inputs:

```txt
--product-root <path>
--rows-root <path>
--proofs <path>
--bindings <path>
--config <path> optional
--policy-mode feature | release | custom
--base-ref <git-ref> optional, for append-only checks if delegated
--json optional
--ci optional
--out <path> optional
```

Must do:

```txt
1. Load YAML rows.
2. Compute current row semantic hashes.
3. Compute verification policy hashes.
4. Compute approval policy hashes.
5. Load and validate binding registry.
6. Scan product source files for markers.
7. Parse markers exactly.
8. Reject forbidden marker payloads.
9. Resolve explicit spans.
10. Resolve Swift inferred spans only if supported and unambiguous.
11. Compute span hashes.
12. Enforce full slug uniqueness.
13. Enforce registered binding requirement.
14. Compute binding_set_hash per row.
15. Load and validate evidence events structurally.
16. Derive row statuses.
17. Emit status object.
18. In CI mode, print computed inferred Swift spans.
```

Must not do:

```txt
1. Must not write source files.
2. Must not write bindings.jsonl.
3. Must not write proofs.jsonl.
4. Must not append proof events.
5. Must not mark anything fresh from comments.
6. Must not do best-effort inference.
```

CI human output must include inferred spans:

```txt
INFERRED SWIFT SPAN
row: checkout.apply_coupon
binding: checkout.apply_coupon#handler
file: Sources/Checkout/CouponService.swift
symbol: applyCoupon
span: lines 13-27
span_sha256: sha256:...
```

Exit codes:

```txt
0 no binding integrity errors and no policy block
1 freshness policy block
2 usage/config/internal error
3 binding integrity failure
4 ledger/registry validation failure
```

In feature mode:

```txt
SUSPECT, UNPROVEN, and UNBOUND do not block.
INVALID blocks.
```

In release mode:

```txt
INVALID blocks.
Any required row not FRESH blocks.
```

## 8.3 `prove`

Purpose:

```txt
Run a row verification policy and append a trusted proof event only after pass.
```

Command:

```txt
use-cases prove \
  --row checkout.apply_coupon \
  --product-root . \
  --rows-root usecases \
  --proofs .use-cases/proofs.jsonl \
  --bindings .use-cases/bindings.jsonl \
  --trusted-ci \
  --signing-key-env USE_CASES_CI_SIGNING_KEY
```

Inputs:

```txt
--row <row_id> or --all
--product-root <path>
--rows-root <path>
--proofs <path>
--bindings <path>
--config <path> optional
--trusted-ci optional
--signing-key-env <env name> optional
--dry-run optional
--json optional
```

Must do:

```txt
1. Run scan first.
2. Refuse to prove INVALID rows.
3. Refuse to prove UNBOUND rows.
4. Run the row's verification_policy.
5. On pass, recompute row hash.
6. On pass, recompute current binding records.
7. On pass, recompute binding_set_hash.
8. Build proof event from recomputed data.
9. Sign proof event in trusted CI mode.
10. Append proof event to proofs.jsonl only after verification pass and signature success.
11. Emit proof result JSON.
```

Must not do:

```txt
1. Must not append evidence for failed verification.
2. Must not accept caller-supplied row_hash.
3. Must not accept caller-supplied span_sha256.
4. Must not accept caller-supplied binding_set_hash.
5. Must not let an agent set producer.kind to trusted-ci-prover.
6. Must not append unsigned proof events.
7. Must not modify source markers.
8. Must not modify binding registry.
```

Local behavior:

```txt
Without --trusted-ci, prove may run verification and emit a candidate report.
It must not append a proof event.
```

Untrusted append attempt:

```txt
If --append is requested without trusted CI credentials:
    exit 6
```

Output example:

```json
{
  "ok": true,
  "command": "prove",
  "trusted": true,
  "row_id": "checkout.apply_coupon",
  "verification_result": "pass",
  "proof_event_appended": true,
  "event_id": "01JABCDEFAAAAAAAAAAAAAAAAAA",
  "row_hash": "sha256:...",
  "binding_set_hash": "sha256:..."
}
```

Exit codes:

```txt
0 verification passed and proof appended, or dry-run candidate passed
2 usage/config/internal error
3 scan found binding integrity failure
4 ledger/registry validation failure
5 verification failed
6 untrusted proof append attempted
```

## 8.4 `validate-ledger`

Purpose:

```txt
Validate append-only discipline, schemas, signatures, and internal hash consistency.
```

Command:

```txt
use-cases validate-ledger \
  --proofs .use-cases/proofs.jsonl \
  --bindings .use-cases/bindings.jsonl \
  --base-ref origin/main \
  --public-key .use-cases/trusted-ci-public-key.pem \
  --json
```

Inputs:

```txt
--proofs <path>
--bindings <path>
--base-ref <git-ref> optional
--public-key <path>
--rows-root <path>
--json optional
```

Must do:

```txt
1. Verify evidence JSONL parses.
2. Verify registry JSONL parses.
3. Verify all events match schema.
4. Verify evidence ledger is append-only relative to base-ref when provided.
5. Verify binding registry is append-only relative to base-ref when provided.
6. Verify proof event signatures.
7. Verify proof event producer is trusted.
8. Verify proof event result is pass.
9. Verify proof event binding_set_hash recomputes from embedded bindings.
10. Verify registry slugs map to existing rows.
11. Verify registry slug uniqueness.
12. Verify no conflicting registry mappings.
```

Must not do:

```txt
1. Must not compare old proof span hashes to current code and call that invalid.
2. Must not mutate ledger.
3. Must not mutate registry.
4. Must not derive freshness. That is scan's job.
```

Output example:

```json
{
  "ok": true,
  "command": "validate-ledger",
  "evidence_valid": true,
  "registry_valid": true,
  "append_only": true,
  "proof_events_checked": 12,
  "registry_events_checked": 5,
  "errors": []
}
```

Exit codes:

```txt
0 valid
2 usage/config/internal error
4 invalid ledger or registry
```

---

# 9. Swift function recognizer

This is the only inferred-end recognizer in v1.

Do not implement this with regex-only scanning. Use a Swift parser/concrete syntax tree if possible. A small lexer plus brace matcher is acceptable only if it rejects every ambiguous case.

## 9.1 Supported form

Supported:

```swift
//: @use-case: row.slug#suffix
@Attribute(...)
@AnotherAttribute
public static func name<T>(...) async throws -> ReturnType
    where T: Constraint {
    ...
}
```

The function may be:

```txt
top-level function
type member function
extension member function
```

Unsupported in v1:

```txt
init
deinit
subscript
var
let
class
struct
enum
protocol requirement without body
computed property
operator declaration if parser cannot classify it as func
macro-generated declaration with no explicit body
nested function inside another function
declaration inside conditional compilation
```

Unsupported means:

```txt
INVALID unless explicit end is used.
```

## 9.2 Placement rule

For inferred Swift:

```txt
The marker must be immediately before the full attached declaration group.
```

Valid:

```swift
//: @use-case: checkout.apply_coupon
@MainActor
public func applyCoupon(...) {
    ...
}
```

Valid:

```swift
//: @use-case: checkout.apply_coupon
public func applyCoupon(...) {
    ...
}
```

Valid:

```swift
//: @use-case: checkout.apply_coupon
func applyCoupon(...) {
    ...
}
```

Invalid:

```swift
@MainActor
//: @use-case: checkout.apply_coupon
public func applyCoupon(...) {
    ...
}
```

Invalid:

```swift
//: @use-case: checkout.apply_coupon

public func applyCoupon(...) {
    ...
}
```

Invalid:

```swift
//: @use-case: checkout.apply_coupon
// TODO: coupon behavior
public func applyCoupon(...) {
    ...
}
```

Reason:

```txt
No blank lines or comments between marker and declaration group in inferred mode.
```

Use explicit end if you want comments or nonstandard placement.

## 9.3 Span extent

Given marker line `M`:

```txt
1. Parse the Swift file.
2. Find the first non-whitespace token after marker line M.
3. That token must be the first token of a supported Swift function declaration node.
4. The function node must include attached attributes and modifiers.
5. The function node must have an explicit body.
6. The body must have a closing brace.
7. The function node must not be nested inside another function.
8. No conditional compilation directive may appear between declaration start and body end.
9. No marker may appear inside the computed span.
10. If any check fails, inference fails closed.
```

Computed span:

```txt
span_start_line = line containing first token of function declaration node,
                  including first attached attribute if present

span_end_line = line containing closing brace of function body

span_start_byte = first byte of span_start_line

span_end_byte = byte after line ending of span_end_line,
                or EOF if closing brace is on final line
```

Hash uses `ucase-span-lines-v1`.

## 9.4 Ambiguity failures

These are invalid for inferred mode:

```txt
NO_SWIFT_PARSER
SWIFT_PARSE_ERROR_IN_REGION
MARKER_NOT_ADJACENT_TO_DECLARATION
MARKER_INSIDE_ATTACHED_DECLARATION
NEXT_NODE_NOT_FUNC
FUNC_HAS_NO_BODY
FUNC_BODY_HAS_NO_CLOSING_BRACE
NESTED_FUNC_UNSUPPORTED
CONDITIONAL_COMPILATION_IN_SPAN
ANOTHER_MARKER_INSIDE_SPAN
MULTIPLE_CANDIDATE_DECLARATIONS
```

Each error should report:

```txt
file
line
slug
reason
fix: add explicit "//: @use-case: end <slug>" or move marker
```

---

# 10. Precommit vs CI

## 10.1 Precommit

Precommit is ergonomics. It is not authority.

Run:

```txt
use-cases validate-ledger --staged
use-cases scan --policy-mode feature
```

Blocks:

```txt
1. malformed marker
2. duplicate slug
3. unclosed or mismatched explicit end
4. unsupported inferred marker
5. unregistered current marker
6. non-append evidence edit
7. non-append registry edit
8. invalid proof event schema
9. invalid proof signature
10. registry conflict
```

Does not block:

```txt
1. SUSPECT row
2. UNPROVEN row
3. UNBOUND row
```

But it must print a loud warning:

```txt
USE-CASE ROW SUSPECT
row: checkout.apply_coupon
reason: CODE_SPAN_CHANGED
required action: use-cases prove --row checkout.apply_coupon
```

## 10.2 CI

CI is authority.

Required CI jobs:

```txt
1. validate-ledger
2. scan
3. prove, when configured
```

Feature branch CI:

```txt
validate-ledger: blocks on failure
scan: blocks INVALID only
freshness: reports SUSPECT/UNPROVEN/UNBOUND loudly, does not block
prove: optional
```

Release branch CI:

```txt
validate-ledger: blocks on failure
scan: blocks INVALID
freshness: blocks required rows that are not FRESH
prove: can mint signed proof events
```

CI must print inferred spans:

```txt
INFERRED SWIFT SPAN
row: checkout.apply_coupon
binding: checkout.apply_coupon#handler
file: Sources/Checkout/CouponService.swift
symbol: applyCoupon
span: lines 13-27
span_sha256: sha256:...
```

Policy gate:

```txt
feature:
    block only INVALID

release:
    block if row.approval_policy.required_for_release == true
    and row.status != FRESH

custom:
    read configured policy expression
```

---

# 11. Lie-guard mutation tests

These tests exist to prevent the living-spec failure mode.

Each mutation must fail exactly as specified.

## 11.1 Marker laundering mutations

| Mutation | Expected failure |
|---|---|
| Add `fresh=true` after slug | INVALID, forbidden marker payload |
| Add `proven=true` after slug | INVALID, forbidden marker payload |
| Add `sha256=...` after slug | INVALID, forbidden marker payload |
| Add `row_hash=...` after slug | INVALID, forbidden marker payload |
| Add `span_hash=...` after slug | INVALID, forbidden marker payload |
| Add `role=impl` after slug | INVALID, forbidden marker payload |
| Add `tier1` after slug | INVALID, forbidden marker payload |
| Use naked `end` with no slug | INVALID, malformed end marker |
| Use mismatched end slug | INVALID, mismatched end marker |

## 11.2 Binding identity mutations

| Mutation | Expected failure |
|---|---|
| Duplicate same full slug in two starts | INVALID, duplicate binding slug |
| Current marker slug missing from registry | INVALID, unregistered binding |
| Registry slug maps to missing row | INVALID |
| Registry slug prefix differs from row_id | INVALID |
| Registry reassigns slug to different row | INVALID |
| Delete marker for registered binding | row SUSPECT, reason BINDING_REMOVED |
| Rename marker slug from old row to new registered slug | old row SUSPECT, new row UNPROVEN |
| Rename marker slug to unregistered slug | INVALID |

## 11.3 Span inference mutations

| Mutation | Expected failure |
|---|---|
| Swift marker followed by blank line before func | INVALID |
| Swift marker followed by comment before func | INVALID |
| Swift marker placed after `@MainActor` | INVALID |
| Swift marker before protocol func with no body | INVALID |
| Swift marker before `var` | INVALID |
| Swift marker before `init` | INVALID |
| Swift marker before nested func | INVALID |
| Swift marker in conditional compilation span | INVALID |
| Swift marker before malformed Swift region | INVALID |
| TypeScript function marker without explicit end | INVALID, unsupported inference |
| Python function marker without explicit end | INVALID, unsupported inference |

## 11.4 Evidence laundering mutations

| Mutation | Expected failure |
|---|---|
| Agent appends unsigned proof event | validate-ledger fails |
| Agent appends proof event with fake producer.kind | validate-ledger fails |
| Agent appends proof event with bad signature | validate-ledger fails |
| Agent appends proof event with `result: fail` | validate-ledger fails |
| Agent edits old evidence line | append-only validation fails |
| Agent deletes old evidence line | append-only validation fails |
| Agent edits old registry line | append-only validation fails |
| Agent deletes old registry line | append-only validation fails |
| Proof event binding_set_hash does not recompute from event bindings | validate-ledger fails |
| Proof event row id does not exist | validate-ledger fails |
| Binder writes evidence event | test fails |
| Scanner writes evidence event | test fails |
| Prover accepts caller-supplied span hash | test fails |
| Prover accepts caller-supplied row hash | test fails |

## 11.5 Freshness mutations

| Mutation | Expected status |
|---|---|
| Edit row YAML after proof | SUSPECT, ROW_HASH_CHANGED |
| Edit marked code span after proof | SUSPECT, CODE_SPAN_CHANGED |
| Add new binding to proven row | SUSPECT, BINDING_ADDED |
| Remove binding from proven row | SUSPECT, BINDING_REMOVED |
| Move binding to new file with same span text | SUSPECT, BINDING_PATH_CHANGED |
| Change verification policy after proof | SUSPECT, VERIFICATION_POLICY_CHANGED |
| Change approval policy after proof | SUSPECT, APPROVAL_POLICY_CHANGED |
| Revert row and span to exactly proven hashes | FRESH if matching trusted proof exists |

---

# 12. Ordered build plan

## Phase 1: Schemas and hash primitives

Build:

```txt
1. canonical_json
2. sha256 helper
3. row hash adapter to existing semantic hash system
4. verification_policy_hash
5. approval_policy_hash
6. binding_set_hash
7. JSON schemas for registry, evidence, status
```

Acceptance criteria:

```txt
1. Same binding set in different order hashes identically.
2. Changing span_sha256 changes binding_set_hash.
3. Changing file_path changes binding_set_hash.
4. Changing line numbers does not change binding_set_hash.
5. Invalid registry event fails schema.
6. Invalid proof event fails schema.
```

## Phase 2: Marker parser and explicit span scanner

Build:

```txt
1. marker line parser
2. configured comment prefix resolver
3. explicit start/end span resolver
4. duplicate slug detection
5. mismatched end detection
6. nested span rejection
7. span canonicalizer
8. current binding record output
```

Acceptance criteria:

```txt
1. Explicit span in a `//` file scans correctly.
2. Explicit span in a configured `#` file scans correctly.
3. Naked end fails.
4. Mismatched end fails.
5. Duplicate start slug fails.
6. Nested span fails.
7. Marker with `sha256=...` fails.
8. Unsupported single marker without end fails.
```

## Phase 3: Append-only binding registry

Build:

```txt
1. bindings.jsonl reader
2. bindings.jsonl validator
3. append-only check against git base-ref
4. materialized registry map
5. unregistered current marker detection
6. missing registered marker detection
```

Acceptance criteria:

```txt
1. bind-registered marker scans valid.
2. manually typed unregistered marker is INVALID.
3. deleting a registered marker produces SUSPECT, not disappearance.
4. editing an old registry line fails validate-ledger.
5. deleting an old registry line fails validate-ledger.
6. conflicting registry mapping fails.
```

## Phase 4: Swift function recognizer

Build:

```txt
1. Swift parser integration or safe Swift recognizer
2. inferred declaration adjacency check
3. attached attribute/modifier inclusion
4. body closing brace detection
5. unsupported form rejection
6. CI span print output
```

Acceptance criteria:

```txt
1. Marker before `@MainActor public func` computes span from `@MainActor` to closing brace.
2. Marker before multiline generic signature with where-clause computes correct span.
3. Marker after `@MainActor` fails.
4. Marker followed by blank line fails.
5. Marker followed by comment fails.
6. Marker before protocol requirement fails.
7. Marker before nested function fails.
8. Marker before TypeScript function without end fails.
9. CI output prints file, symbol, lines, and span hash.
```

## Phase 5: Evidence ledger validation and trusted proof signatures

Build:

```txt
1. proofs.jsonl reader
2. proof event schema validator
3. ed25519 signature verifier
4. ed25519 signer for trusted CI prove
5. append-only check against git base-ref
6. proof event internal binding_set_hash recomputation
```

Acceptance criteria:

```txt
1. Valid signed proof event passes.
2. Unsigned proof event fails.
3. Bad signature fails.
4. Edited old evidence line fails.
5. Deleted old evidence line fails.
6. Proof event with bad binding_set_hash fails.
7. Old proof whose span differs from current code does not fail validation by itself.
```

## Phase 6: Freshness state machine

Build:

```txt
1. row status derivation
2. FRESH predicate
3. SUSPECT reason derivation
4. UNPROVEN predicate
5. UNBOUND predicate
6. INVALID propagation
7. policy gate
```

Acceptance criteria:

```txt
1. New row with no registry binding = UNBOUND.
2. New registered binding with no proof = UNPROVEN.
3. Passing proof matching row and binding set = FRESH.
4. Row edit after proof = SUSPECT.
5. Marked span edit after proof = SUSPECT.
6. Marker removal after registry = SUSPECT.
7. Reprove after span edit = FRESH.
8. Feature policy does not block SUSPECT.
9. Release policy blocks required SUSPECT row.
```

## Phase 7: CLI tools

Build:

```txt
1. bind
2. scan
3. prove
4. validate-ledger
5. JSON output for all tools
6. exit codes
```

Acceptance criteria:

```txt
1. bind can place explicit markers and register slug.
2. bind can place inferred Swift marker and register slug.
3. bind never writes evidence.
4. scan never writes source, registry, or evidence.
5. prove without trusted CI never appends evidence.
6. prove with trusted CI appends signed proof on pass.
7. prove does not append on fail.
8. validate-ledger catches schema/signature/append-only failures.
```

## Phase 8: Precommit and CI wiring

Build:

```txt
1. precommit script
2. CI validate-ledger job
3. CI scan job
4. CI proof job
5. release policy mode
6. PR annotations or textual summary
```

Acceptance criteria:

```txt
1. Precommit blocks malformed markers.
2. Precommit blocks non-append ledger edit.
3. Precommit warns but does not block SUSPECT row.
4. Feature CI blocks INVALID only.
5. Release CI blocks required row not FRESH.
6. CI prints inferred Swift spans.
7. CI proof job can mint signed proof event.
```

## Phase 9: Lie-guard mutation suite

Build the mutation tests listed above.

Acceptance criteria:

```txt
Every mutation fails with the expected error/status.
No mutation can produce FRESH without a trusted passing proof event.
```

---

# 13. Smallest walking skeleton

Ship this first.

## 13.1 Row

YAML row:

```yaml
id: checkout.apply_coupon
actor: shopper
intent: apply a valid coupon to a cart
preconditions:
  - cart exists
  - coupon exists
trigger: shopper enters coupon code
scenario_steps:
  - shopper submits coupon code
  - system validates coupon
  - system applies discount
observable_outcomes:
  - cart total reflects discount
verification_policy:
  command: npm run test:usecase -- checkout.apply_coupon
approval_policy:
  required_for_release: true
  trusted_producer: trusted-ci-prover
```

## 13.2 Product code

Swift source:

```swift
//: @use-case: checkout.apply_coupon
@MainActor
public func applyCoupon<T>(_ code: String, cart: T) async throws -> CouponResult
    where T: CartLike {
    let coupon = try await couponRepository.find(code)
    return try cart.apply(coupon)
}
```

## 13.3 Bind

Run:

```txt
use-cases bind \
  --row checkout.apply_coupon \
  --file Sources/Checkout/CouponService.swift \
  --line 1 \
  --mode swift-func
```

Expected:

```txt
bindings.jsonl gets one binding_registered event.
scan computes Swift function span.
row status = UNPROVEN.
```

## 13.4 First scan

Run:

```txt
use-cases scan --policy-mode feature --json
```

Expected row status:

```txt
UNPROVEN
```

No integrity failure.

## 13.5 First trusted proof

Run in trusted CI:

```txt
use-cases prove --row checkout.apply_coupon --trusted-ci
```

Expected:

```txt
verification command passes
signed proof event appended to proofs.jsonl
```

Then:

```txt
use-cases scan --policy-mode feature --json
```

Expected:

```txt
FRESH
```

## 13.6 Code drift

Edit marked Swift function body:

```swift
return CouponResult.noDiscount
```

Run:

```txt
use-cases scan --policy-mode feature --json
```

Expected:

```txt
SUSPECT
reason: CODE_SPAN_CHANGED
policy_block: false
required_action: use-cases prove --row checkout.apply_coupon
```

## 13.7 Reprove

Run in trusted CI:

```txt
use-cases prove --row checkout.apply_coupon --trusted-ci
```

Expected:

```txt
new signed proof event appended
scan returns FRESH
```

## 13.8 Marker removal bypass test

Delete:

```swift
//: @use-case: checkout.apply_coupon
```

Run:

```txt
use-cases scan --policy-mode feature --json
```

Expected:

```txt
SUSPECT
reason: ALL_BINDINGS_REMOVED
row does not vanish from report
```

## 13.9 Re-slug bypass test

Change marker to:

```swift
//: @use-case: checkout.remove_coupon
```

After registering the new slug properly, scan should report:

```txt
checkout.apply_coupon: SUSPECT, BINDING_REMOVED
checkout.remove_coupon: UNPROVEN
```

If the new slug is not registered:

```txt
INVALID, UNREGISTERED_BINDING
```

---

# Final judgment

This v1 is buildable.

The most important parts are not the Swift recognizer or the marker syntax. They are these mechanical boundaries:

```txt
1. Source comments contain identity only.
2. Binding registry is append-only.
3. Proof events are signed by trusted CI.
4. Freshness is recomputed from row hash plus current binding set.
5. Inference fails closed.
```

Do those, and this is no longer living-doc theater. It becomes a narrow, enforceable behavior-binding system with honest stale detection.