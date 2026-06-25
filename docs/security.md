# Security And Trust

Generated plans, migration output, capsules, and host projections are prepared
material only. They are not proof.

Trusted user approval must come through a trusted user path. In v1 that path is
the CLI-mediated `showcase approve --actor user` flow. MCP tools can request
approval but cannot fabricate it.

Append-only ledgers preserve accidental or disputed history through correction
events. Normal commands do not physically delete evidence or showcase history.
Physical purge for secrets or legal requirements needs a separate destructive
workflow with explicit audit output.

Host profiles are expectation data. A host executable smoke result or projection
manifest can help diagnose setup, but verified host support requires recorded
evidence IDs.

Package checks reject local/session state such as `.albus/`, `.cowork-receipts/`,
`.Codex/`, build locks, `node_modules/`, and coverage output.
