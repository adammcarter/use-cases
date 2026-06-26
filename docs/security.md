# Security And Trust

Generated plans, migration output, capsules, and host projections are prepared
material only. They are not proof.

Trusted user approval must come through a trusted user path. In v1 that path is
interactive CLI confirmation from the user. Future host-token approval must be a
trusted non-model confirmation path. MCP tools can request approval but cannot
fabricate it.

Approval proof is bound to the generated plan hash and the finish event for the
run. Generated plans, capsules, and runbooks are prepared material until a run
records events against them.

Append-only ledgers preserve accidental or disputed history through correction
events. Normal commands do not physically delete evidence or showcase history.
Physical purge for secrets or legal requirements needs a separate destructive
workflow with explicit audit output.

Host profiles are expectation data. A host executable smoke result or projection
manifest can help diagnose setup, but verified host support requires recorded
evidence IDs.

Package checks inspect real tarballs or installed package roots. They reject
local/session state such as `.albus/`, `.cowork-receipts/`, `.Codex/`, build
locks, packaged `node_modules/`, coverage output, local absolute paths, and
secret-looking values.
