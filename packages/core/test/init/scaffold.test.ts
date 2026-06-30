import { describe, expect, test } from "vitest";
import { nextSteps } from "../../src/init/scaffold.js";

// `ucp init` prints next_steps to onboard a brand-new adopter. Those steps must
// only cite docs that actually ship in the published package — pointing at a doc
// that is not shipped dead-ends the adopter the moment they follow the link.
//
// The shipped doc set is the flat `docs/*.md` files declared in the package
// `files` field (plus `docs/adr/`). Nested doc trees (concepts/, reference/,
// security/, tutorials/) and `getting-started.md` are NOT published, so they
// must never appear in onboarding guidance.

const SHIPPED_DOCS = new Set([
  "docs/acceptance.md",
  "docs/activation.md",
  "docs/cli.md",
  "docs/data-model.md",
  "docs/hosts.md",
  "docs/markers-adoption.md",
  "docs/mcp.md",
  "docs/migration.md",
  "docs/release.md",
  "docs/security.md",
  "docs/showcase.md"
]);

function docRefsIn(line: string): string[] {
  return [...line.matchAll(/docs\/[A-Za-z0-9_./-]+\.md/g)].map((m) => m[0]);
}

describe("ucp init next_steps doc references", () => {
  const steps = nextSteps();

  test("every cited docs/*.md path is a shipped doc", () => {
    const cited = steps.flatMap(docRefsIn);
    for (const ref of cited) {
      expect(SHIPPED_DOCS, `next_steps cites non-shipped doc ${ref}`).toContain(ref);
    }
  });

  test("never cites a known non-shipped doc or nested doc tree", () => {
    const joined = steps.join("\n");
    expect(joined).not.toContain("getting-started");
    expect(joined).not.toMatch(/docs\/concepts\//);
    expect(joined).not.toMatch(/docs\/reference\//);
    expect(joined).not.toMatch(/docs\/security\//);
    expect(joined).not.toMatch(/docs\/tutorials\//);
  });
});
