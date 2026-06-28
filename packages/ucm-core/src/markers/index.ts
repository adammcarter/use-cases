// Public API for the use-case-markers Phase 1 primitives:
// schema ids/constants, canonical JSON + sha256, the row/policy/binding-set
// hashes, and the JSON-schema validators.
export * from "./constants.js";
export * from "./canonicalJson.js";
export * from "./rowHash.js";
export * from "./policyHash.js";
export * from "./verifierResolver.js";
export * from "./verificationContextHash.js";
export * from "./bindingSetHash.js";
export * from "./validators.js";
// Phase 2: marker parser + explicit-span scanner.
export * from "./commentPrefix.js";
export * from "./markerLine.js";
export * from "./spanCanon.js";
export * from "./physicalLines.js";
export * from "./scanner.js";
// Phase 4: Swift function recognizer (inferred-end spans).
export * from "./swiftFuncRecognizer.js";
// Phase 3: append-only binding registry + reconciliation.
export * from "./registry.js";
export * from "./appendOnly.js";
export * from "./reconcile.js";
// Phase 5: evidence ledger validation + trusted-CI proof signatures.
export * from "./proofSignature.js";
export * from "./evidenceLedger.js";
// Phase 6: freshness state machine (status derivation + policy gate).
export * from "./freshness.js";
// Phase 7: CLI command cores (bind / scan / prove / validate-ledger).
export * from "./cli/index.js";
