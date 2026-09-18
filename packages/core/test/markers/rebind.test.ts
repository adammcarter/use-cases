// Re-pointing and releasing a binding (`use-cases rebind` / `use-cases unbind`).
//
// A marker on the wrong declaration is the vacuous-row defect in marker form: the
// row reads as proven while the code it points at cannot fail when the claim does.
// Before these two commands existed, `bind` was the only writer of a binding and a
// slug could be registered exactly once, so a review that FOUND such a row had
// nothing it could do about it — `bind` refused with DUPLICATE_REGISTRATION, and
// removing the markers from source did not release the registration.
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runRebindCommand,
  runScanCommand,
  runUnbindCommand,
  runVerifyCommand,
  validateBindingsJsonl,
  type VerifySpawnRunner
} from "../../src/markers/index.js";

const ROW_ID = "checkout.apply_coupon";
const GENERATED_AT = "2026-07-30T09:00:00.000Z";

const CONFIG_YAML = `schema_version: 1
workspace_id: rebind.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: rebind-fixture
default_workflow_mode: continuous
`;

function useCaseYaml(rowId: string): string {
  return `schema_version: 1
feature:
  id: checkout
  name: Checkout
  summary: Shoppers can apply coupons during checkout.
metadata:
  owner: product
  lifecycle: active
use_cases:
  - id: ${rowId}
    title: Apply a valid coupon
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: Apply a valid coupon to a cart.
    preconditions:
      - A cart exists.
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: ${rowId}.web
        kind: steps
        steps:
          - The shopper submits a coupon code.
    observable_outcomes:
      - The cart total reflects the discount.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        contract_check:
          kind: script
          evidence_kind: test_result
          command: [echo, contract-ok]
          inputs: []
      requirements:
        - evidence_kind: test_result
          required_verifiers: [contract_check]
          minimum_count: 1
    approval_policy:
      mode: predefined
      requirements:
        - approver_type: user
          minimum_count: 1
      statement: Final acceptance requires user-visible proof.
`;
}

// The shape of the real defect: a declaration that merely CONSTRUCTS the server
// and advertises that tools exist (cannot fail when a host rejects the schema),
// followed by the declaration that actually calls through the contract.
const SOURCE = `import Foundation

public func makeServer() -> Server {
    return Server(tools: ["search"])
}

public func callThroughContract(_ name: String) throws -> Response {
    return try dispatch(name)
}
`;

const tempDirs: string[] = [];
afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

interface Workspace {
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  context: ReturnType<typeof resolveWorkspaceContext>;
}

function writeFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

function makeWorkspace(sourceFiles: Record<string, string> = {}): Workspace {
  const root = mkdtempSync(join(tmpdir(), "rebind-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", useCaseYaml(ROW_ID));
  for (const [relPath, contents] of Object.entries(sourceFiles)) {
    writeFile(root, relPath, contents);
  }
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  return {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl"),
    context
  };
}

let idCounter = 0;
const clock = () => GENERATED_AT;
const idFactory = () => `01JREBIND${String(idCounter++).padStart(17, "0")}`;

const SOURCE_PATH = "Sources/Checkout/Server.swift";

function bindWrongDeclaration(ws: Workspace) {
  return runBindCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    rowId: ROW_ID,
    file: SOURCE_PATH,
    mode: "swift-func",
    line: 3, // makeServer: cannot fail when the claim does
    clock,
    idFactory
  });
}

function scan(ws: Workspace) {
  return runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode: "feature",
    publicKeyResolver: () => undefined,
    generatedAt: GENERATED_AT
  });
}

function source(ws: Workspace): string {
  return readFileSync(join(ws.productRoot, SOURCE_PATH), "utf8");
}

function bindingsText(ws: Workspace): string {
  return readFileSync(ws.bindingsPath, "utf8");
}

function markerLines(text: string): string[] {
  return text.split("\n").filter((line) => line.includes("@use-case:"));
}

const passSpawn: VerifySpawnRunner = () => ({
  exit_code: 0,
  timed_out: false,
  stdout: "ok\n",
  stderr: ""
});

function verify(ws: Workspace) {
  return runVerifyCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: () => undefined,
    trustedKeyConfigured: false,
    generatedAt: GENERATED_AT,
    rowId: ROW_ID,
    spawnRunner: passSpawn,
    outPath: join(ws.context.data_root, ".use-cases", "verification-results.jsonl")
  });
}

function localStatus(ws: Workspace): string | undefined {
  const row = scan(ws).status.rows.find((entry) => entry.row_id === ROW_ID);
  return row?.local_status ?? undefined;
}

// The reason codes scan reports for one row (BINDING_REMOVED and friends).
function rowReasons(result: ReturnType<typeof runScanCommand>, rowId: string): string[] {
  const row = result.status.rows.find((entry) => entry.row_id === rowId);
  return (row?.reasons ?? []).map((reason) => reason.code);
}

describe("use-cases unbind: releasing a binding", () => {
  test("removes the marker and releases the registration, so the slug can be bound again", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    expect(bindWrongDeclaration(ws).exit_code).toBe(0);
    expect(markerLines(source(ws))).toHaveLength(1);

    const result = runUnbindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      clock,
      idFactory
    });

    expect(result.errors).toEqual([]);
    expect(result.exit_code).toBe(0);
    expect(result.registry_event_appended).toBe(true);
    expect(result.markers_removed).toEqual([
      { file_path: SOURCE_PATH, start_line: 3, end_line: null }
    ]);
    // Marker gone from the source, registration gone from the live registry.
    expect(markerLines(source(ws))).toEqual([]);
    const validated = validateBindingsJsonl(bindingsText(ws), new Set([ROW_ID]));
    expect(validated.errors).toEqual([]);
    expect(validated.registry.slugToRow.has(ROW_ID)).toBe(false);
    // Scan is clean: a released binding is not a removed one.
    expect(scan(ws).status.integrity_errors).toEqual([]);

    // The dead end is gone: bind accepts the slug again.
    const rebound = runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: SOURCE_PATH,
      mode: "swift-func",
      line: 7, // callThroughContract, now that the markers are gone
      clock,
      idFactory
    });
    expect(rebound.errors).toEqual([]);
    expect(rebound.exit_code).toBe(0);
  });

  test("releases a row that has already left the matrix, clearing REGISTRY_ROW_MISSING", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    expect(bindWrongDeclaration(ws).exit_code).toBe(0);
    // The behaviour is retired: the row is deleted from the matrix while bound.
    writeFile(ws.productRoot, "use-cases/checkout.yml", useCaseYaml("checkout.other_row"));
    expect(scan(ws).exit_code).toBe(4);

    const result = runUnbindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      reason: "row_retired",
      clock,
      idFactory
    });

    expect(result.errors).toEqual([]);
    expect(result.exit_code).toBe(0);
    expect(scan(ws).status.integrity_errors).toEqual([]);
    expect(scan(ws).exit_code).toBe(0);
  });

  test("releases a registration whose markers were already removed by hand", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    expect(bindWrongDeclaration(ws).exit_code).toBe(0);
    writeFile(ws.productRoot, SOURCE_PATH, SOURCE); // markers stripped out again
    expect(rowReasons(scan(ws), ROW_ID)).toContain("BINDING_REMOVED");

    const result = runUnbindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      clock,
      idFactory
    });

    expect(result.exit_code).toBe(0);
    expect(result.markers_removed).toEqual([]);
    expect(result.registry_event_appended).toBe(true);
    expect(scan(ws).status.integrity_errors).toEqual([]);
    expect(rowReasons(scan(ws), ROW_ID)).not.toContain("BINDING_REMOVED");
  });

  test("refuses a slug that is not registered, and writes nothing", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    const result = runUnbindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      clock,
      idFactory
    });
    expect(result.exit_code).toBe(2);
    expect(result.errors.map((e) => e.code)).toEqual(["NOT_REGISTERED"]);
    expect(result.registry_event_appended).toBe(false);
    expect(markerLines(source(ws))).toEqual([]);
  });

  test("--dry-run reports the release without touching source or registry", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    bindWrongDeclaration(ws);
    const before = { src: source(ws), ledger: bindingsText(ws) };

    const result = runUnbindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      dryRun: true,
      clock,
      idFactory
    });

    expect(result.exit_code).toBe(0);
    expect(result.registry_event_appended).toBe(false);
    expect(result.markers_removed).toHaveLength(1);
    expect(source(ws)).toBe(before.src);
    expect(bindingsText(ws)).toBe(before.ledger);
  });
});

describe("use-cases rebind: moving a binding to the right declaration", () => {
  test("moves the marker and re-registers in one step", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    expect(bindWrongDeclaration(ws).exit_code).toBe(0);

    const result = runRebindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: SOURCE_PATH,
      mode: "swift-func",
      line: 7, // callThroughContract, once the old marker line is gone
      clock,
      idFactory
    });

    expect(result.errors).toEqual([]);
    expect(result.exit_code).toBe(0);
    expect(result.moved_from).toEqual({ file_path: SOURCE_PATH, start_line: 3, end_line: null });
    // The proven span is the body of the declaration the marker now sits on.
    expect(result.scan_result?.span_start_line).toBe(8);
    // Exactly one marker in the source, on the declaration that can fail.
    const lines = source(ws).split("\n");
    expect(markerLines(source(ws))).toHaveLength(1);
    expect(lines[6]).toContain(`@use-case:${ROW_ID}`);
    expect(lines[7]).toContain("callThroughContract");
    // One release + one registration, appended (never rewritten).
    const events = bindingsText(ws)
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line) as { event_type: string; reason: string });
    expect(events.map((e) => e.event_type)).toEqual([
      "binding_registered",
      "binding_released",
      "binding_registered"
    ]);
    expect(events[2].reason).toBe("rebind");
    expect(scan(ws).status.integrity_errors).toEqual([]);
  });

  test("moves a binding across files", () => {
    const OTHER = "Sources/Checkout/Dispatch.swift";
    const ws = makeWorkspace({
      [SOURCE_PATH]: SOURCE,
      [OTHER]: "import Foundation\n\npublic func dispatch(_ name: String) throws -> Response {\n    return Response()\n}\n"
    });
    expect(bindWrongDeclaration(ws).exit_code).toBe(0);

    const result = runRebindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: OTHER,
      mode: "swift-func",
      line: 3,
      clock,
      idFactory
    });

    expect(result.errors).toEqual([]);
    expect(result.moved_from?.file_path).toBe(SOURCE_PATH);
    expect(result.file_path).toBe(OTHER);
    expect(markerLines(source(ws))).toEqual([]);
    expect(markerLines(readFileSync(join(ws.productRoot, OTHER), "utf8"))).toHaveLength(1);
    expect(scan(ws).status.integrity_errors).toEqual([]);
  });

  test("refuses an unbound row and points at bind", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    const result = runRebindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: SOURCE_PATH,
      mode: "swift-func",
      line: 3,
      clock,
      idFactory
    });
    expect(result.exit_code).toBe(2);
    expect(result.errors.map((e) => e.code)).toEqual(["NOT_REGISTERED"]);
    expect(result.errors[0].message).toContain("use-cases bind");
    expect(markerLines(source(ws))).toEqual([]);
  });

  // Fail-closed, like bind: an unresolvable target must leave the source and the
  // ledger exactly as they were, not strand the row registered to nothing.
  test("a target that cannot resolve to a span leaves source and registry untouched", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    bindWrongDeclaration(ws);
    const before = { src: source(ws), ledger: bindingsText(ws) };

    const result = runRebindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: SOURCE_PATH,
      mode: "swift-func",
      line: 2, // a blank line: the next node is not a func
      clock,
      idFactory
    });

    expect(result.exit_code).not.toBe(0);
    expect(result.errors).not.toEqual([]);
    expect(source(ws)).toBe(before.src);
    expect(bindingsText(ws)).toBe(before.ledger);
    // Still bound where it was, so nothing is lost by a failed rebind.
    expect(scan(ws).status.integrity_errors).toEqual([]);
  });
});

// The property that makes re-pointing safe to offer at all. A binding that moves
// is a DIFFERENT claim about the code, so the proof of the old one must not
// travel with it — otherwise `rebind` would be a way to launder a verified status
// onto code nobody has verified, which is worse than the dead end it replaces.
describe("a moved binding does not carry its proof", () => {
  test("VERIFIED_LOCAL does not survive a rebind, and re-verifying restores it", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    expect(bindWrongDeclaration(ws).exit_code).toBe(0);
    expect(verify(ws).exit_code).toBe(0);
    expect(localStatus(ws)).toBe("VERIFIED_LOCAL");

    const moved = runRebindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: SOURCE_PATH,
      mode: "swift-func",
      line: 7,
      clock,
      idFactory
    });
    expect(moved.exit_code).toBe(0);

    // The row is no longer locally verified: the binding set it was verified
    // against does not exist any more.
    // STALE_LOCAL, not VERIFIED_LOCAL: the row is visibly out of date, not silently fine.
    expect(localStatus(ws)).toBe("STALE_LOCAL");
    expect(moved.next_command).toBe(`use-cases verify --row ${ROW_ID}`);

    // ...and the keyless loop puts it back, now proving the RIGHT declaration.
    expect(verify(ws).exit_code).toBe(0);
    expect(localStatus(ws)).toBe("VERIFIED_LOCAL");
    expect(scan(ws).status.integrity_errors).toEqual([]);
  });

  test("unbind leaves nothing behind claiming the row is verified", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: SOURCE });
    bindWrongDeclaration(ws);
    verify(ws);
    expect(localStatus(ws)).toBe("VERIFIED_LOCAL");

    const released = runUnbindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      clock,
      idFactory
    });
    expect(released.exit_code).toBe(0);
    expect(localStatus(ws)).not.toBe("VERIFIED_LOCAL");
  });
});

// Paths the new commands support but nothing exercised end to end yet. The exec
// bit in particular: `bind` regressed on exactly this once (an atomic rewrite
// dropping 100755 to 100644 on a bound hook), so the two commands that rewrite
// the same way get the same guard.
describe("moving one binding does not disturb its neighbours", () => {
  const TWO_FUNCS = `import Foundation

public func first() -> Int {
    return 1
}

public func second() -> Int {
    return 2
}

public func third() -> Int {
    return 3
}
`;

  function bindWithSuffix(ws: Workspace, suffix: string, line: number) {
    return runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      suffix,
      file: SOURCE_PATH,
      mode: "swift-func",
      line,
      clock,
      idFactory
    });
  }

  test("a row with two suffixed bindings moves only the one named", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: TWO_FUNCS });
    expect(bindWithSuffix(ws, "alpha", 3).exit_code).toBe(0);
    // The alpha marker shifted everything below it down one line.
    expect(bindWithSuffix(ws, "beta", 8).exit_code).toBe(0);
    expect(markerLines(source(ws))).toHaveLength(2);

    const moved = runRebindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      suffix: "alpha",
      file: SOURCE_PATH,
      mode: "swift-func",
      line: 12, // third(), counted with the alpha marker gone and beta's still in
      clock,
      idFactory
    });

    expect(moved.errors).toEqual([]);
    expect(moved.binding_slug).toBe(`${ROW_ID}#alpha`);
    // Both bindings still exist, and beta never moved.
    const lines = source(ws).split("\n");
    expect(markerLines(source(ws))).toHaveLength(2);
    expect(lines.findIndex((l) => l.includes(`${ROW_ID}#beta`))).toBe(6);
    expect(lines[7]).toContain("second()");
    expect(scan(ws).status.integrity_errors).toEqual([]);
  });

  test("releasing one suffixed binding leaves the other registered", () => {
    const ws = makeWorkspace({ [SOURCE_PATH]: TWO_FUNCS });
    bindWithSuffix(ws, "alpha", 3);
    bindWithSuffix(ws, "beta", 8);

    const released = runUnbindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      suffix: "alpha",
      clock,
      idFactory
    });

    expect(released.exit_code).toBe(0);
    const validated = validateBindingsJsonl(bindingsText(ws), new Set([ROW_ID]));
    expect(validated.errors).toEqual([]);
    expect([...(validated.registry.rowToSlugs.get(ROW_ID) ?? [])]).toEqual([`${ROW_ID}#beta`]);
    expect(markerLines(source(ws))).toHaveLength(1);
    expect(scan(ws).status.integrity_errors).toEqual([]);
  });

  test.each([
    ["rebind", "rebind"],
    ["unbind", "unbind"]
  ])("%s keeps a bound script executable", (command) => {
    const HOOK = "hooks/session-start";
    const ws = makeWorkspace({ [HOOK]: "#!/bin/sh\necho one\necho two\necho three\n" });
    const hookAbs = join(ws.productRoot, HOOK);
    chmodSync(hookAbs, 0o755);
    expect(
      runBindCommand({
        context: ws.context,
        productRoot: ws.productRoot,
        bindingsPath: ws.bindingsPath,
        rowId: ROW_ID,
        file: HOOK,
        mode: "explicit",
        startLine: 2,
        endLine: 2,
        clock,
        idFactory
      }).exit_code
    ).toBe(0);
    expect(statSync(hookAbs).mode & 0o111).not.toBe(0);

    const result =
      command === "rebind"
        ? runRebindCommand({
            context: ws.context,
            productRoot: ws.productRoot,
            bindingsPath: ws.bindingsPath,
            rowId: ROW_ID,
            file: HOOK,
            mode: "explicit",
            startLine: 3,
            endLine: 4,
            clock,
            idFactory
          })
        : runUnbindCommand({
            context: ws.context,
            productRoot: ws.productRoot,
            bindingsPath: ws.bindingsPath,
            rowId: ROW_ID,
            clock,
            idFactory
          });

    expect(result.exit_code).toBe(0);
    // 100755 survives the atomic temp+rename, as it must for a bound hook.
    expect(statSync(hookAbs).mode & 0o111).not.toBe(0);
  });
});
