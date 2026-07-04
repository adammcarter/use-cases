// Phase 7 CLI command cores: bind / scan / prove / validate-ledger.
//
// Pure-ish command functions taking injectable fs/git/clock/verification-runner,
// so they are unit-testable against a tmp dir without shelling out. The thin
// cli wiring parses argv, resolves a workspace context, and calls these.
export * from "./io.js";
export * from "./shared.js";
export * from "./scan.js";
export * from "./bind.js";
export * from "./prove.js";
export * from "./verify.js";
// 0.2.0 F2: advisory, read-only change-impact map (`uc impact`).
export * from "./impact.js";
export * from "./validateLedger.js";
// Phase 8: precommit orchestrator + PR-summary formatter (pure, unit-tested).
export * from "./precommit.js";
