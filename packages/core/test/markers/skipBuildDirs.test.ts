// collectSourceInputs must skip build-output dirs (dist/, build/, ...). tsc
// preserves the `//:` marker comment into dist/, so without this a built repo
// would see the same slug in src AND dist -> a false DUPLICATE_BINDING_SLUG.
// Surfaced by dogfooding markers on real (built) repo code.
import { afterEach, describe, expect, test } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { collectSourceInputs, scanFiles } from "../../src/markers/index.js";

const SRC = `//: @use-case:demo.row
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

  // `examples/` was one instance of a general rule that was never generalised:
  // a directory carrying its own use-cases.yml is its OWN workspace, and its
  // markers name its own rows. This repo's CI was red for exactly that reason —
  // tests/fixtures/backcompat is a nested workspace whose checkout.* markers the
  // parent scan read as ROW_NOT_FOUND.
  test("a marker in any nested workspace is not scanned by the parent", () => {
    const root = mkdtempSync(join(tmpdir(), "ucm-skip-nested-"));
    dirs.push(root);
    write(root, "packages/core/src/F.ts", SRC);
    write(root, "tests/fixtures/backcompat/use-cases.yml", "schema_version: 1\nworkspace_id: fixture\n");
    write(root, "tests/fixtures/backcompat/src/coupon.js", SRC);

    expect(collectSourceInputs(root).map((i) => i.file_path).sort()).toEqual(["packages/core/src/F.ts"]);
  });

  test("a nested workspace is skipped whatever it is called", () => {
    // The rule is the config file, not a blessed directory name — otherwise the
    // next nested workspace needs another hardcoded entry in the skip list.
    const root = mkdtempSync(join(tmpdir(), "ucm-skip-nested-any-"));
    dirs.push(root);
    write(root, "src/F.ts", SRC);
    write(root, "vendor/demo-app/use-cases.yml", "schema_version: 1\nworkspace_id: demo\n");
    write(root, "vendor/demo-app/src/F.ts", SRC);

    expect(collectSourceInputs(root).map((i) => i.file_path).sort()).toEqual(["src/F.ts"]);
  });

  test("the product root's own use-cases.yml does not skip the whole repo", () => {
    // The guard must apply to nested directories only. Treating the root's own
    // config as a nested workspace would scan nothing at all.
    const root = mkdtempSync(join(tmpdir(), "ucm-skip-nested-root-"));
    dirs.push(root);
    write(root, "use-cases.yml", "schema_version: 1\nworkspace_id: parent\n");
    write(root, "src/F.ts", SRC);

    expect(collectSourceInputs(root).map((i) => i.file_path)).toContain("src/F.ts");
  });

  test("a marker in a nested examples/ project is not scanned by the parent", () => {
    // examples/ ship their own matrix + markers (a nested workspace); scanning
    // them from the parent repo would read their rows as INVALID. They must be
    // skipped by default. Regression for the python-pytest example leaking
    // `example.checkout.apply_coupon` into the parent root scan.
    // Skipped now because every shipped example carries its own use-cases.yml,
    // not because the directory is called `examples` — the fixture writes that
    // config so it represents a real example rather than a bare directory.
    const root = mkdtempSync(join(tmpdir(), "ucm-skip-examples-"));
    dirs.push(root);
    write(root, "packages/core/src/F.ts", SRC); // the parent's real marker
    write(root, "examples/python-pytest/use-cases.yml", "schema_version: 1\nworkspace_id: example\n");
    write(root, "examples/python-pytest/src/coupon.py", SRC); // nested example marker

    const scanned = collectSourceInputs(root)
      .map((i) => i.file_path)
      .sort();
    expect(scanned).toEqual(["packages/core/src/F.ts"]);
  });
});
