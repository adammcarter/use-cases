import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { scaffoldWorkspace } from "../../src/init/scaffold.js";
import { scanFileForMarkers } from "../../src/markers/scanner.js";

// `uc init --template js-vitest` must scaffold a RUNNABLE example out of the
// box — mirroring the python-pytest template, which ships a real marked source
// file plus a matching test at the preset's expected path. Without both files a
// new adopter cannot run `verify` until they hand-write them, so the js-vitest
// template is not runnable as scaffolded. These tests pin the runnable example.
//
// The example row id is `example.feature.happy_path` (the row scaffolded in
// use-cases/example.yml). The js.vitest preset runs
//   pnpm -s vitest run tests/use-cases/<row-id>.test.ts
// so the acceptance test MUST live at tests/use-cases/example.feature.happy_path.test.ts.

const ROW_ID = "example.feature.happy_path";
const SRC_REL = "src/example.ts";
const TEST_REL = `tests/use-cases/${ROW_ID}.test.ts`;

describe("uc init --template js-vitest scaffolds a runnable example", () => {
  let repoRoot: string;

  beforeEach(() => {
    repoRoot = mkdtempSync(join(tmpdir(), "ucm-init-jsvitest-"));
  });

  afterEach(() => {
    rmSync(repoRoot, { recursive: true, force: true });
  });

  test("creates the marked source file and the vitest test at the preset path", () => {
    const result = scaffoldWorkspace({ repoRoot, template: "js-vitest" });
    expect(result.status).toBe("created");
    expect(result.created_files).toContain(SRC_REL);
    expect(result.created_files).toContain(TEST_REL);
  });

  test("the source file carries a valid marker span for the example row id", () => {
    scaffoldWorkspace({ repoRoot, template: "js-vitest" });
    const srcPath = join(repoRoot, SRC_REL);
    const contents = readFileSync(srcPath, "utf8");
    // `//` is the `.ts` comment prefix, so the span markers are the JS spelling.
    expect(contents).toContain(`//: @use-case: ${ROW_ID}`);
    expect(contents).toContain(`//: @use-case: end ${ROW_ID}`);

    const scan = scanFileForMarkers(SRC_REL, contents);
    expect(scan.errors).toEqual([]);
    expect(scan.bindings.map((b) => b.row_id)).toContain(ROW_ID);
  });

  test("the acceptance test imports from the scaffolded source", () => {
    scaffoldWorkspace({ repoRoot, template: "js-vitest" });
    const testContents = readFileSync(join(repoRoot, TEST_REL), "utf8");
    // The test must reference the source module so it actually exercises the
    // marked implementation rather than a placeholder.
    expect(testContents).toMatch(/from\s+["']\.\.\/\.\.\/src\/example(?:\.js)?["']/);
    expect(testContents).toMatch(/expect\(/);
  });

  test("only the js-vitest template ships the runnable source+test pair", () => {
    const generic = scaffoldWorkspace({ repoRoot, template: "generic" });
    expect(generic.created_files).not.toContain(SRC_REL);
    expect(generic.created_files).not.toContain(TEST_REL);
  });
});
