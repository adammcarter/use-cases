// Phase 7 CLI command cores: bind / scan / prove / validate-ledger.
//
// Pure-ish command functions taking injectable fs/git/clock/verification-runner,
// so they are unit-testable against a tmp dir without shelling out. The thin
// ucm-cli wiring parses argv, resolves a workspace context, and calls these.
export * from "./io.js";
export * from "./shared.js";
export * from "./scan.js";
export * from "./bind.js";
export * from "./prove.js";
export * from "./validateLedger.js";
