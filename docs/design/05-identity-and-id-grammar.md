# 05 — Identity & ID Grammar

This document defines the grammar and stability rules for Use Cases identifiers.

## Core rule

Identifiers are designed to be:

- human-readable
- deterministic
- stable
- portable across languages and filesystems
- safe to embed in markers and tooling

Examples in this chapter use a small Swift project. Nothing in the rules depends on it: the shapes are the same for any language and tool.

## Allowed characters

ID segments may contain:

```text
a-z
0-9
-
```

Namespace separators use:

```text
.
```

Reserved structural characters include:

```text
#
```

## Segment rules

A segment:

- must be lowercase
- must contain only `a-z`, `0-9`, or `-`
- must not begin with `-`
- must not end with `-`
- must not be empty

Valid examples:

```text
login
sign-in
oauth2
ipv6
3d
v2
```

Invalid examples:

```text
Login
sign_in
-signin
signin-
sign in
```

## Namespace rules

A namespace is one or more valid segments joined with `.`.

Valid:

```text
app
app.auth
app.auth.login
renderer.3d.preview
legacy.v2.import
```

Invalid:

```text
app..login
.app.login
app.login.
App.Login
app/auth/login
```

`.` is reserved for namespace composition.

## Local IDs

Local IDs are single segments.

Examples:

```text
success
invalid-password
oauth2-callback
```

They must not contain `.`.

Local IDs are composed with explicit YAML prefixes to form full IDs.

```text
prefix: app.auth.login
local id: success

        |
        v

app.auth.login.success
```

## Full use-case IDs

A full use-case ID is the resolved namespace produced by explicit YAML composition.

Example:

```text
app.auth.login.success
```

The full resolved ID is the immutable identity of the use case.

Filesystem paths and filenames never contribute implicitly to identity.

## Validation route IDs

Validation route IDs are local single-segment IDs.

Examples:

```text
unit-tests
full-app-acceptance
preview-check
```

They are stable once used in derived identities.

## Binding IDs

Binding IDs are local single-segment IDs.

Examples:

```text
submit-login
create-session
valid-credentials
invalid-password
```

A binding ID comes from one of two places:

- a marker in the code, which carries it after `#` (see below)
- a manual binding's `id` in the use case YAML

They are stable once used in derived identities.

## Validation IDs

Validation IDs name the entries under `validations:` in `use-cases-bridge.yml` (`10 — Bridge settings + transformer contract`).

They are local single-segment IDs, unique within the bridge settings.

`record` is reserved: it names verdicts recorded with `use-cases record` and can never be a validation ID.

Examples:

```text
auth-tests
all-tests
legacy-integration
```

Results record which validation produced them, so validation IDs are stable once used.

## Link keys

Every resolved link gets a key assigned by the core:

```text
<use-case-id>#[<route-id>.]<binding-id>@<file>:<start-line>
```

Example:

```text
app.auth.login.authenticate#unit-tests.valid-credentials@Tests/LoginTests.swift:6
```

`<file>` is the link's workspace path exactly as spelled on disk, spaces, `@`, `:` and non-ASCII characters included. A key is split at its first `@` and its last `:`, which the grammar makes unambiguous. Keys are opaque to transformers: they receive keys and echo them back, and never build or parse them.

Transformers name links by this key. Keys are run-local handles, not persistent identity: moving code changes a key without changing the binding.

A key names exactly one region. Two regions with one key (the same binding twice on one line) are INVALID.

## Derived marker identities

Implementation marker:

```text
<use-case-id>#<binding-id>
```

Example:

```text
app.auth.login.authenticate#submit-login
```

Validation marker:

```text
<use-case-id>#<validation-route-id>.<binding-id>
```

Example:

```text
app.auth.login.authenticate#unit-tests.valid-credentials
```

`#` is reserved for separating the use-case identity from the marker-local identity.

`.` after `#` composes validation-route and binding IDs.

## Stability

These IDs are stable once they participate in persistent identity:

- full use-case IDs
- validation route IDs
- binding IDs
- validation IDs

Changing one is treated as a rename/replacement operation, not an ordinary edit.

Mutable fields such as titles, descriptions, procedures, run commands, and file locations may change without changing identity.

## Summary grammar

```text
segment
  = [a-z0-9] ([a-z0-9-]* [a-z0-9])?

namespace
  = segment ("." segment)*

use-case-id
  = namespace

route-id
  = segment

binding-id
  = segment

validation-id
  = segment

implementation-marker
  = use-case-id "#" binding-id

validation-marker
  = use-case-id "#" route-id "." binding-id

link-key
  = use-case-id "#" [route-id "."] binding-id "@" file ":" start-line
```

The exact parser/regex implementation is deferred to the technical specification.
