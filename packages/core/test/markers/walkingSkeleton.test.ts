// Walking-skeleton end-to-end test (spec section 13).
//
// Drives the full loop against a REAL temp workspace using the actual CLI command
// cores (bind/scan/prove/validate-ledger) with an injected verification runner, a
// generated ed25519 keypair, and an injected clock — so the whole bind -> scan ->
// prove -> drift -> reprove -> bypass story runs deterministically and offline.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import {
  runBindCommand,
  runProveCommand,
  runScanCommand,
  type FreshnessRowOut
} from "../../src/markers/index.js";
import { UCP_VERSION } from "../../src/version.js";
import {
  ALLOW_UNSAFE_ENV,
  cleanupWorkspaces,
  makeClock,
  makeId,
  makeWorkspace,
  resolver,
  GENERATED_AT,
  KEY_ID,
  PRIVATE_KEY,
  ROW_ID,
  ROW_ID_2,
  SWIFT_FUNC_SOURCE,
  type Workspace
} from "./helpers.js";

afterEach(cleanupWorkspaces);

// prove no longer runs the verifier itself; it consumes verification results. The
// walking skeleton just needs a signed proof to exist, so it drives prove via the
// env-gated unsafe-assume seam (the documented test path) rather than minting a
// results ledger for the fixture's user-actor verifier (which never resolves to a
// runnable script).
let previousUnsafe: string | undefined;
beforeEach(() => {
  previousUnsafe = process.env[ALLOW_UNSAFE_ENV];
  process.env[ALLOW_UNSAFE_ENV] = "1";
});
afterEach(() => {
  if (previousUnsafe === undefined) {
    delete process.env[ALLOW_UNSAFE_ENV];
  } else {
    process.env[ALLOW_UNSAFE_ENV] = previousUnsafe;
  }
});

const SWIFT_REL = "Sources/Checkout/CouponService.swift";

function scan(ws: Workspace, policyMode: "feature" | "release" = "feature") {
  return runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
}

function prove(ws: Workspace) {
  return runProveCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    rowId: ROW_ID,
    generatedAt: GENERATED_AT,
    idFactory: makeId("01JPROVE"),
    trustedCi: true,
    unsafeAssumeVerificationResult: "pass",
    signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID }
  });
}

function bindApplyCoupon(ws: Workspace) {
  return runBindCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    rowId: ROW_ID,
    file: SWIFT_REL,
    mode: "swift-func",
    line: 3,
    clock: makeClock(),
    idFactory: makeId("01JBIND")
  });
}

function rowOf(result: ReturnType<typeof runScanCommand>, rowId: string): FreshnessRowOut {
  const row = result.status.rows.find((entry) => entry.row_id === rowId);
  if (!row) {
    throw new Error(`row ${rowId} missing from status`);
  }
  return row;
}

function reasonCodes(row: FreshnessRowOut): string[] {
  return row.reasons.map((reason) => reason.code);
}

function sourcePath(ws: Workspace): string {
  return join(ws.productRoot, SWIFT_REL);
}

describe("walking skeleton (spec section 13)", () => {
  test("a-f: bind -> UNPROVEN -> prove FRESH -> drift SUSPECT -> reprove FRESH -> delete-marker bypass SUSPECT", () => {
    const ws = makeWorkspace({ [SWIFT_REL]: SWIFT_FUNC_SOURCE });

    // (b) bind (swift-func) -> registry has exactly one binding_registered event;
    // scan -> row UNPROVEN.
    const bindResult = bindApplyCoupon(ws);
    expect(bindResult.exit_code).toBe(0);
    expect(bindResult.registry_event_appended).toBe(true);
    expect(bindResult.scan_result?.extent_kind).toBe("swift_func_inferred");

    const registryLines = readFileSync(ws.bindingsPath, "utf8").trim().split("\n");
    expect(registryLines).toHaveLength(1);
    expect(JSON.parse(registryLines[0]).binding_slug).toBe(ROW_ID);
    // A bind that is not handed an explicit producer version stamps the real
    // product version into created_by, not a stale hard-coded default.
    expect(JSON.parse(registryLines[0]).created_by.version).toBe(UCP_VERSION);

    const afterBind = scan(ws);
    expect(afterBind.exit_code).toBe(0);
    expect(rowOf(afterBind, ROW_ID).status).toBe("UNPROVEN");
    // The freshness status envelope reports the real product version.
    expect(afterBind.status.tool.version).toBe(UCP_VERSION);

    // (c) prove (trusted, pass) -> one signed proof appended; scan -> FRESH.
    const proveResult = prove(ws);
    expect(proveResult.exit_code).toBe(0);
    expect(proveResult.proof_events_appended).toBe(1);
    const evidenceLines = readFileSync(ws.evidencePath, "utf8").trim().split("\n");
    expect(evidenceLines).toHaveLength(1);
    const proofEvent = JSON.parse(evidenceLines[0]);
    expect(proofEvent.producer.kind).toBe("trusted-ci-prover");
    expect(proofEvent.verification.result).toBe("pass");
    // A prove that is not handed an explicit producer version stamps the real
    // product version into the signed event, not a stale hard-coded default.
    expect(proofEvent.producer.version).toBe(UCP_VERSION);

    const afterProve = scan(ws);
    expect(rowOf(afterProve, ROW_ID).status).toBe("FRESH");

    // (d) edit the marked Swift function body -> scan -> SUSPECT, CODE_SPAN_CHANGED,
    // policy_block false (feature), required_action present.
    const drifted = readFileSync(sourcePath(ws), "utf8").replace("return 1", "return 2");
    writeFileSync(sourcePath(ws), drifted);

    const afterDrift = scan(ws);
    const driftRow = rowOf(afterDrift, ROW_ID);
    expect(driftRow.status).toBe("SUSPECT");
    expect(reasonCodes(driftRow)).toContain("CODE_SPAN_CHANGED");
    expect(driftRow.policy_block).toBe(false);
    expect(driftRow.required_action).toBe(`ucp prove --row ${ROW_ID}`);
    // Feature mode does not block a SUSPECT row.
    expect(afterDrift.exit_code).toBe(0);

    // (e) reprove (trusted, pass) -> scan -> FRESH again.
    const reprove = prove(ws);
    expect(reprove.exit_code).toBe(0);
    expect(reprove.proof_events_appended).toBe(1);
    expect(readFileSync(ws.evidencePath, "utf8").trim().split("\n")).toHaveLength(2);

    const afterReprove = scan(ws);
    expect(rowOf(afterReprove, ROW_ID).status).toBe("FRESH");

    // (f) BYPASS: delete the marker line -> scan -> SUSPECT (ALL_BINDINGS_REMOVED),
    // and the row does NOT vanish from the report.
    const withoutMarker = readFileSync(sourcePath(ws), "utf8")
      .split("\n")
      .filter((line) => !line.includes("@use-case:"))
      .join("\n");
    writeFileSync(sourcePath(ws), withoutMarker);

    const afterDelete = scan(ws);
    const deletedRow = rowOf(afterDelete, ROW_ID); // throws if the row vanished
    expect(deletedRow.status).toBe("SUSPECT");
    expect(reasonCodes(deletedRow)).toContain("BINDING_REMOVED");
    expect(reasonCodes(deletedRow)).toContain("ALL_BINDINGS_REMOVED");
    expect(deletedRow.missing_registered_binding_slugs).toEqual([ROW_ID]);
    // The bypass cannot make the row disappear or block freshness in feature mode.
    expect(afterDelete.exit_code).toBe(0);
  });

  test("g: re-slug to a properly registered row -> old SUSPECT BINDING_REMOVED, new UNPROVEN", () => {
    const ws = makeWorkspace({ [SWIFT_REL]: SWIFT_FUNC_SOURCE });
    bindApplyCoupon(ws);

    // Re-slug the in-source marker from the old row to the new row id.
    const reslugged = readFileSync(sourcePath(ws), "utf8").replace(
      `//: @use-case: ${ROW_ID}`,
      `//: @use-case: ${ROW_ID_2}`
    );
    writeFileSync(sourcePath(ws), reslugged);

    // Register the new slug properly (register-existing: no further source edit).
    const reRegister = runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID_2,
      file: SWIFT_REL,
      mode: "swift-func",
      registerExisting: true,
      clock: makeClock(),
      idFactory: makeId("01JBIND2")
    });
    expect(reRegister.exit_code).toBe(0);
    expect(reRegister.registry_event_appended).toBe(true);

    const result = scan(ws);
    const oldRow = rowOf(result, ROW_ID);
    const newRow = rowOf(result, ROW_ID_2);
    expect(oldRow.status).toBe("SUSPECT");
    expect(reasonCodes(oldRow)).toContain("BINDING_REMOVED");
    expect(newRow.status).toBe("UNPROVEN");
    // No INVALID rows -> feature scan does not block.
    expect(result.exit_code).toBe(0);
  });

  test("g (negative): re-slug to an UNREGISTERED row -> new row INVALID, UNREGISTERED_BINDING", () => {
    const ws = makeWorkspace({ [SWIFT_REL]: SWIFT_FUNC_SOURCE });
    bindApplyCoupon(ws);

    // Re-slug to the second row WITHOUT registering it.
    const reslugged = readFileSync(sourcePath(ws), "utf8").replace(
      `//: @use-case: ${ROW_ID}`,
      `//: @use-case: ${ROW_ID_2}`
    );
    writeFileSync(sourcePath(ws), reslugged);

    const result = scan(ws);
    const oldRow = rowOf(result, ROW_ID);
    const newRow = rowOf(result, ROW_ID_2);
    // The old row's registered binding is now missing -> SUSPECT (not vanished).
    expect(oldRow.status).toBe("SUSPECT");
    expect(reasonCodes(oldRow)).toContain("BINDING_REMOVED");
    // The new, unregistered marker is INVALID -> binding integrity failure (exit 3).
    expect(newRow.status).toBe("INVALID");
    expect(reasonCodes(newRow)).toContain("UNREGISTERED_BINDING");
    expect(result.exit_code).toBe(3);
  });
});
