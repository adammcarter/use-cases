# Design

How Use Cases is built, and why it is built that way.

This is the architecture document. It describes the repository as it stands: a
pure-Swift product in four packages, distributed as an agent plugin that
downloads and verifies its own binaries. It is **not** a history — how the
repository got here is `docs/adr/0007-swift-rewrite.md` and `CHANGELOG.md` — and
it is not the pitch, which is `README.md`. What it tries to answer is: *if I
have to change this, where does the change go, and what will it break?*

---

## 1. The shape

```
                        the agent host (Claude Code, Codex, Copilot, OpenCode)
                                        │
                  host manifest names a script in this checkout
                                        ▼
   bin/use-cases ─┐                                    ┌─ bin/use-cases-mcp
                  ├──► bin/use-cases-runtime ──────────┤
                  │      (which runtime? decided on    │
                  │       the plugin's VERSION)        │
                  └──► bin/use-cases-bootstrap ────────┘
                         download the release asset for this machine,
                         verify it against the release's SHA256SUMS,
                         cache it, exec it
                                        │
            ┌───────────────────────────┴──────────────────────────┐
            ▼                                                      ▼
   ┌──────────────────┐                                  ┌──────────────────┐
   │  use-cases       │  UseCasesCLI                     │  use-cases-mcp   │  UseCasesMCP
   │  argv → envelope │  swift-argument-parser           │  JSON-RPC/stdio  │  swift-sdk (transport only)
   └────────┬─────────┘                                  └─────────┬────────┘
            └────────────────────┬─────────────────────────────────┘
                                 ▼
                    ┌────────────────────────────┐
                    │        UseCasesCore        │   Yams · swift-crypto
                    │  every rule, every shape,  │
                    │  every byte of JSON we emit│
                    └─────────────┬──────────────┘
                                  │ reads and appends
                                  ▼
        use-cases/*.yml   ·   .use-cases/*.jsonl   ·   schemas/v1/*.json
        the matrix            bindings, proofs,        the frozen contract
                              verification results

   ┌──────────────────────────────────────────────────────────────────┐
   │  UseCasesOracle — depends on NOTHING. Reaches both binaries as   │
   │  processes (UC_BIN / UC_MCP_BIN) and compares their JSON.        │
   └──────────────────────────────────────────────────────────────────┘
```

Four `Package.swift` files in one repository, each buildable on its own. Two
executables ship; the third and fourth packages are a library and a test suite.
Everything targets macOS 14 and Swift 6.

---

## 2. UseCasesCore — the product

`UseCasesCore/Sources/UseCasesCore` is the whole product. The CLI and the MCP
server are two ways of calling it and nothing else: neither holds a rule, a
default or a message the other does not. That is the property the oracle exists
to keep true, and the reason `mcp.wrapper.parity` is a row in the matrix.

It has one library dependency for reading YAML (Yams) and one for cryptography
(swift-crypto: SHA-256 and Ed25519). Nothing else.

The areas, each a directory:

| area | what lives there |
|---|---|
| `Schema/` | The JSON substrate: a hand-written JSON parser and writer, canonical JSON, a JSON-Schema validator driven by the 27 published schemas, the CLI result envelope, semantic hashing. |
| `UseCases/` | The matrix: loading `use-cases/**/*.yml`, validating rows against the schema, listing, upserting, soft-removing. |
| `Markers/` | The trust core: the `@use-case:` marker grammar, the append-only binding registry, verifier resolution and presets, `verify`, `prove`, `scan`, `impact`, `recover`, and the freshness derivation that turns all of it into a status. |
| `Evidence/` | The append-only evidence ledger: recording, replay, completeness, voiding, assurance tiers. |
| `Showcase/` | Event-sourced live runs: start, observe, verdict, decide, pause, resume, finish, approval. |
| `Presentation/` | Plan selection — which rows a showcase or walkthrough should cover, and why the others were excluded. |
| `Capsules/`, `Skills/`, `Agents/`, `Initialization/`, `Workspace/`, `Errors/`, `Foundation/` | Demo capsules, the shipped skill and agent assets, `init` scaffolding, root resolution and path containment, the public error-code registry, and the small shared primitives (`ProductVersion`, `Redactor`, `CanonicalIdentifier`). |

### Why the JSON is written by hand

`JSONWriter` and `CanonicalJSON` exist because `JSONEncoder` cannot promise the
bytes. Key order, number formatting and escaping are part of the contract: a
`semantic_hash` is a SHA-256 over canonical JSON, and a proof that hashes
differently on a different Foundation version is not a proof. Every envelope the
product emits goes through `JSONWriter`, and `JavaScriptNumber` exists so a
number round-trips the way the published schemas were written to expect.

### Everything is derived, nothing is asserted

The matrix, the binding registry, the evidence ledger and showcase runs are all
append-only. No file records a status. `scan` recomputes every row's freshness
from the code on disk, the registry and the proofs, every time. This is the
single decision the rest of the design falls out of: it is why there is a
canonical JSON writer, why hashes are everywhere, and why a correction is a new
event rather than an edit.

---

## 3. UseCasesCLI — argv to envelope

`UseCasesCLI` builds one executable, `use-cases`, with about fifty commands.

Every command is a `CommandSpecification`: a path (`["matrix", "upsert"]`), a
command name for the envelope (`matrix.upsert`), a summary, its flags, and a
closure that produces `data` or throws a `CommandFailure`. The help text, the
dispatch table and the unknown-flag diagnostics are all generated from those
specifications, so a command cannot exist and be undiscoverable.

`Arguments/` scans argv *before* swift-argument-parser sees it. The reason is
the contract: an unknown flag, an unknown subcommand and a bare invocation each
have a defined envelope and a defined exit code, and a parser that exits on its
own would replace them with its own message. swift-argument-parser is used for
the typed flag surface behind that scan, not as the front door.

Output is human-readable by default. `--json` emits the envelope — `ok`,
`complete`, `data`, `diagnostics`, `context` — and `Rendering/` owns the
human-readable form of it (`EnvelopeRenderer`, and `TrustRenderer` for the
scan/verify/impact/recover/showcase surfaces), so the text and the JSON are
two views of one value rather than two things that can disagree.

---

## 4. UseCasesMCP — the same envelopes over stdio

`UseCasesMCP` builds `use-cases-mcp`. Its tools are the CLI's commands: the
same `UseCasesCore` call, the same envelope, so an agent gets identical answers
whichever transport it reaches for.

It depends on the official MCP Swift SDK, **for its `StdioTransport` only**.
The SDK's `Server` encodes responses with its own `JSONEncoder`, has no
`command`/`mutability` fields on a tool descriptor, and negotiates the protocol
version — so it cannot emit the frozen envelope. ADR 0007's amendment of
2026-09-17 records the owner's choice: keep the freeze, keep the SDK for the
pipe, and own the JSON-RPC dispatch and the response bytes ourselves
(`Server/`, writing through `JSONWriter`).

Writes are gated twice, with distinct error codes: the session must be in write
mode (`mcp.server_write_mode_required`) and the call must ask for it
(`mcp.write_mode_required`). `Resources/` and `Prompts/` expose the matrix,
the schemas and the loop's guidance as MCP resources and prompts.

---

## 5. UseCasesOracle — the suite that links nothing

`UseCasesOracle` is a test target with **no dependencies at all**, and that is
the design.

An oracle that linked `UseCasesCore` could shortcut an assertion through the
very code it is meant to hold to account — assert that the product's parser
reads what the product's writer wrote, and prove nothing. So it reaches the
product the only honest way: as processes named by `UC_BIN` and `UC_MCP_BIN`,
compared on their JSON. It carries its own JSON reader (`OracleJson`) and its
own YAML reader (`OracleYaml`), both small and both loud — `OracleYaml` throws
on anything it does not understand rather than returning an empty mapping,
because a reader that quietly returns nothing makes every "this key is absent"
assertion pass having read no file.

The cost is that `swift test` here does not build the binaries: they must exist
and be pointed at, and a missing one fails loudly instead of falling back.
`HarnessTests` pins exactly that.

It also holds the checks that are about the repository rather than the product —
the CI and release workflows are parsed, not grepped; the host manifests are
joined to the binary's reported version; and
`Matrix/ScenarioConventions.swift` holds the matrix to the scenario naming rules
in `docs/rewrite/scenario-conventions.md`.

---

## 6. The plugin — download, verify, exec

There is no npm package, no committed binary and nothing to build on install. A
host installs this repository as a plugin and its manifest names a script in
`bin/`.

- **`bin/use-cases` / `bin/use-cases-mcp`** are two-line entry points. The
  session-start hook puts `bin/` on `PATH`, so a skill or agent just runs
  `use-cases …`.
- **`bin/use-cases-runtime`** is the single place that decides what actually
  runs, so no manifest, hook or doc has to know. It branches on the plugin's
  own version, read from `.claude-plugin/plugin.json`, *before* anything is
  fetched: at or above the first Swift release it goes to the bootstrap; below
  it, nothing runs and it says so, because those releases provably published no
  Swift archive and the Node bundle they used to fall back to has been deleted.
  **The version bump is the cut-over** — that is the whole switch.
- **`bin/use-cases-bootstrap`** resolves the machine's platform, downloads the
  release archive for the installed version, verifies its SHA-256 against the
  release's published `SHA256SUMS`, caches the executables under the per-user
  cache directory and execs the one it was asked for. It never execs a binary
  it has not checksummed, and there is no fallback out of that path: a release
  that should carry assets and does not must fail loudly rather than quietly
  running something older.

Published platform: `macos-arm64` only. Adding one back means the bootstrap's
list and the release workflow's loop, together.

The host manifests — `.claude-plugin/`, `.codex-plugin/`, `opencode/` with its
`package.json` — each declare the same plugin to a different host. A test joins
them to the binary: each declares what the binary reports, they agree with each
other, and the version is never below the first Swift release, which would mean
the plugin refusing to run itself.

---

## 7. The matrix is the spec

`use-cases/**/*.yml` is not documentation about the product. It is the product's
specification, and this repository is its own first user.

A row is a behaviour: intent, preconditions, trigger, scenarios, observable
outcomes, value tier, journey role, host applicability, and a
`verification_policy` saying what would count as proof. Scenarios carry their
role in their id — `<row-id>.golden|bad|edge|stress[_<qualifier>]` — so
"every active row has a bad path" is a check rather than an assertion; the rules
are in `docs/rewrite/scenario-conventions.md` and the check is a Swift test.

The chain from a row to a trustworthy claim:

```
  row in use-cases/*.yml
        │  use-cases bind   (writes @use-case: markers into the source)
        ▼
  a code span, registered in .use-cases/bindings.jsonl        (append-only)
        │  use-cases verify (runs the row's verifier)
        ▼
  an UNSIGNED result in .use-cases/verification-results.jsonl
        │  use-cases prove  (trusted CI only; Ed25519 key held as a secret)
        ▼
  a SIGNED proof event in the evidence ledger                  (append-only)
        │  use-cases scan   (recomputes, every time)
        ▼
  FRESH / SUSPECT / UNPROVEN / UNBOUND / INVALID
```

Edit the bound code and the span's hash moves, so the signed proof no longer
matches and the row reads `SUSPECT` on its own. No one can type `FRESH`. The
local half of the loop (`verify` → `VERIFIED_LOCAL`) needs no key and is what a
developer or an agent runs; only CI can mint the signed tier.

`use-cases scan --gate` is what a release leans on: required rows must reach the
policy's floor or the gate fails.

---

## 8. Variant families

One logical behaviour often has many input shapes — `0/1/many`, empty, boundary,
negative — that share a verifier. A row may declare them:

```yaml
- id: cart.quantity
  title: Cart quantity handling across input shapes
  variants:
    - key: zero
      title: Rejects a zero quantity
    - key: many
      title: Accepts a large quantity
```

The **family is the one bindable row**. That is forced rather than chosen: the
marker grammar is `row-id ["#" suffix]`, so `cart.quantity::zero` is not a legal
slug and a variant cannot carry a marker. One marker in code, one binding, the
slug grammar untouched.

Everything else fans out from there:

- **verify** resolves the family's single verifier once per declared variant,
  substituting the key into a `{variant}` token exactly as `{slug}` is
  substituted (`VerifierPresets`). Each spawn's exit code is that variant's
  verdict — the same rule an ordinary row already uses, so no new report
  format and no new parser. A family whose command omits `{variant}` is a
  surfaced spec error, because a command that cannot tell the variants apart
  must not silently prove them all identically.
- **Identity.** Each variant is addressable as `family::key`. It inherits the
  family's binding span but computes its own `row_hash` and
  `binding_set_hash` from its own id, so editing one variant invalidates only
  that variant's evidence.
- **The ledger.** N spawns produce N records written in **one** merge-write,
  keyed by `row_id` as it always was. Variant rows are simply more ids in the
  same keyspace; siblings and unrelated rows are preserved untouched.
- **scan** gives each variant its own `local_status` and the family is green
  only when every variant is; the weakest variant wins and the reason names it.
- **Targeting is family-level.** `verify --row cart.quantity::zero` answers
  `ROW_NOT_FOUND` (measured): a variant is addressable in the ledger, not on the
  command line. `recover` is the one command that accepts a `::` id, and only
  because it is handed one by `scan` — it reduces it to the family before acting
  (`RecoverCommands+Run.familyRowIdentifier`), which is not variant targeting
  either.

A row with no `variants` key behaves exactly as it did before the feature
existed, byte for byte. That is load-bearing, and it rests on one rule: **only
ever hash what the author literally wrote.** `semantic_hash` covers the whole
row value, so materialising a default — injecting `variants: []` onto a row that
omits it — would silently move that row's hash and invalidate its stored
evidence. Optional fields are pass-through on load, and a test pins it.

The version floor is the honest cost: `use-case-file.schema.json` sets
`additionalProperties: false`, so an older binary reading a `variants`-bearing
matrix rejects it with a loud `schema_error`. Safe — never a misread — but
adopting variants means everyone on that repository upgrades.

---

## 9. What is frozen

ADR 0007 decision 8 freezes four things, and a change that needs one of them
stops and asks the owner:

1. the CLI JSON envelope,
2. the 27 published schemas under `schemas/v1/`,
3. the marker syntax,
4. the ledger formats.

Everything else is ordinary code. Notably **not** frozen: internal module
boundaries, the human-readable rendering, help text, and filesystem layout — the
default fixture path `schema validate-fixtures` reaches for is a path, not a
contract, and it moved with its directory in the 0.8.0 clean-up.

The three internal marker schemas live in `schemas/markers/`, deliberately a
sibling of `schemas/v1/` rather than inside it: everything that enumerates the
published set names `schemas/v1` exactly, so the internal ones cannot leak into
the 27. `EmbeddedSchemas.swift` is generated from the files by
`UseCasesCore/Scripts/generate-embedded-schemas.swift`, and a drift test is the
only thing stopping the embedded copies and the committed files parting.

---

## 10. Where everything lives

| path | what it is |
|---|---|
| `UseCasesCore/`, `UseCasesCLI/`, `UseCasesMCP/`, `UseCasesOracle/` | the four Swift packages |
| `bin/` | the plugin entry points, the runtime switch and the download-and-verify bootstrap |
| `.claude-plugin/`, `.codex-plugin/`, `opencode/`, `package.json` | one host manifest each; `package.json` is OpenCode's, not a build manifest |
| `skills/`, `agents/`, `hooks/`, `bootstrap/` | what the plugin installs into a host |
| `schemas/v1/` | the 27 published schemas — frozen |
| `schemas/markers/` | three internal schemas, embedded into the binary |
| `use-cases/` | this repository's own matrix — the spec |
| `.use-cases/` | its bindings, proofs and verification results — append-only |
| `evidence/`, `showcase-runs/` | recorded evidence and performed showcase runs |
| `fixtures/` | data, not tests: the conformance workspaces and captures of published 0.4.x/0.5.5 binaries |
| `examples/`, `demo-capsules/` | runnable examples and packaged demos |
| `docs/` | the documentation index, the concepts, the ADRs and the rewrite record |

Corpus files (`*GoldenCorpus.swift`) are a category of their own and worth
knowing about before editing one. They are recorded bytes — argv in, stdout and
written files out — and their generators were retired with the TypeScript, so
they are **not regenerable**. Each says so in its header. A case that has to
change is changed by hand, deliberately, with the reason written down, and the
question to answer first is always the same: is this value an **output** the
binary produces now, or a **record** of what some earlier install wrote? Outputs
move with the product. Records do not.
