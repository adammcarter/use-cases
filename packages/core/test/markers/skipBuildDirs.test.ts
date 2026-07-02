// collectSourceInputs must skip build-output dirs (dist/, build/, ...). tsc
// preserves the `//:` marker comment into dist/, so without this a built repo
// would see the same slug in src AND dist -> a false DUPLICATE_BINDING_SLUG.
// Surfaced by dogfooding markers on real (built) repo code.
import { afterEach, describe, expect, test } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { collectSourceInputs, scanFiles } from "../../src/markers/index.js";

const SRC = `//: @use-case: demo.row
public func f() -> Int {
    return 1
}
`;

const dirs: string[] = [];
afterEach(() => {
  while (dirs.length > 0) {
    const d = dirs.pop();
    if (d) rmSync(d, { recursive: true, force: true });
  }
});

function write(root: string, rel: string, body: string): void {
  const full = join(root, rel);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, body);
}

describe("collectSourceInputs skips build-output dirs", () => {
  test("a marker copied into dist/ is not scanned (no duplicate slug)", () => {
    const root = mkdtempSync(join(tmpdir(), "ucm-skip-"));
    dirs.push(root);
    write(root, "Sources/F.swift", SRC); // the real source marker
    write(root, "dist/F.js", SRC); // tsc-preserved copy in build output
    write(root, "build/F.js", SRC); // another build dir

    const inputs = collectSourceInputs(root);
    const scanned = inputs.map((i) => i.file_path).sort();
    expect(scanned).toEqual(["Sources/F.swift"]);

    // And the full scan yields exactly one binding, no duplicate-slug error.
    const result = scanFiles(inputs, {});
    expect(result.errors).toEqual([]);
    expect(result.bindings.map((b) => b.binding_slug)).toEqual(["demo.row"]);
  });

  test("a marker inside .claude/worktrees (a repo COPY) is not scanned", () => {
    // Workflow isolation creates full repo copies under .claude/worktrees/; their
    // source markers would otherwise duplicate the real slug and poison the scan.
    const root = mkdtempSync(join(tmpdir(), "ucm-skip-claude-"));
    dirs.push(root);
    write(root, "Sources/F.swift", SRC); // the real source marker
    write(root, ".claude/worktrees/wf-1/Sources/F.swift", SRC); // a leftover copy

    const inputs = collectSourceInputs(root);
    expect(inputs.map((i) => i.file_path).sort()).toEqual(["Sources/F.swift"]);
    const result = scanFiles(inputs, {});
    expect(result.errors).toEqual([]);
    expect(result.bindings.map((b) => b.binding_slug)).toEqual(["demo.row"]);
  });

  test("a marker in a nested examples/ project is not scanned by the parent", () => {
    // examples/ ship their own matrix + markers (a nested workspace); scanning
    // them from the parent repo would read their rows as INVALID. They must be
    // skipped by default. Regression for the python-pytest example leaking
    // `example.checkout.apply_coupon` into the parent root scan.
    const root = mkdtempSync(join(tmpdir(), "ucm-skip-examples-"));
    dirs.push(root);
    write(root, "packages/core/src/F.ts", SRC); // the parent's real marker
    write(root, "examples/python-pytest/src/coupon.py", SRC); // nested example marker

    const scanned = collectSourceInputs(root)
      .map((i) => i.file_path)
      .sort();
    expect(scanned).toEqual(["packages/core/src/F.ts"]);
  });
});
