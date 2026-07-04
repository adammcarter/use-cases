import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { scaffoldWorkspace } from "../../src/init/scaffold.js";

const ROW_ID = "example.feature.happy_path";
const TEST_REL = `tests/use-cases/${ROW_ID}.test.ts`;

function generatedTestContents(repoRoot: string): string {
  return readFileSync(join(repoRoot, TEST_REL), "utf8");
}

describe("uc init package-manager-specific scaffold commands", () => {
  let repoRoot: string;

  beforeEach(() => {
    repoRoot = mkdtempSync(join(tmpdir(), "ucm-init-pm-"));
  });

  afterEach(() => {
    rmSync(repoRoot, { recursive: true, force: true });
  });

  test("emits the pnpm vitest command when the target workspace has a pnpm lockfile", () => {
    writeFileSync(join(repoRoot, "pnpm-lock.yaml"), "lockfileVersion: 9\n", "utf8");

    scaffoldWorkspace({ repoRoot, template: "js-vitest" });

    expect(generatedTestContents(repoRoot)).toContain(`//   pnpm -s vitest run ${TEST_REL}`);
  });

  test("emits the npm vitest command when the target workspace has an npm lockfile", () => {
    writeFileSync(join(repoRoot, "package-lock.json"), "{}\n", "utf8");

    scaffoldWorkspace({ repoRoot, template: "js-vitest" });

    expect(generatedTestContents(repoRoot)).toContain(`//   npm exec -- vitest run ${TEST_REL}`);
    expect(generatedTestContents(repoRoot)).not.toContain("pnpm -s vitest");
  });

  test("emits the yarn vitest command when the target workspace has a yarn lockfile", () => {
    writeFileSync(join(repoRoot, "yarn.lock"), "\n", "utf8");

    scaffoldWorkspace({ repoRoot, template: "js-vitest" });

    expect(generatedTestContents(repoRoot)).toContain(`//   yarn vitest run ${TEST_REL}`);
    expect(generatedTestContents(repoRoot)).not.toContain("pnpm -s vitest");
  });

  test("emits the bun vitest command when the target workspace has a bun lockfile", () => {
    writeFileSync(join(repoRoot, "bun.lockb"), "\n", "utf8");

    scaffoldWorkspace({ repoRoot, template: "js-vitest" });

    expect(generatedTestContents(repoRoot)).toContain(`//   bun x vitest run ${TEST_REL}`);
    expect(generatedTestContents(repoRoot)).not.toContain("pnpm -s vitest");
  });

  test("emits the neutral npx vitest command when the target workspace has no lockfile", () => {
    scaffoldWorkspace({ repoRoot, template: "js-vitest" });

    expect(generatedTestContents(repoRoot)).toContain(`//   npx vitest run ${TEST_REL}`);
    expect(generatedTestContents(repoRoot)).not.toContain("pnpm -s vitest");
  });
});
