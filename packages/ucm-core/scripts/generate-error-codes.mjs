// Regenerates `docs/reference/error-codes.md` from the compiled error-code
// registry. Run `pnpm -s build` first, then:
//   node packages/ucm-core/scripts/generate-error-codes.mjs
// A test (`test/errors/registry.test.ts`) asserts the on-disk file stays in sync.

import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../..");

const { renderErrorCodesMarkdown } = await import(
  resolve(here, "../dist/errors/render.js")
);

const target = resolve(repoRoot, "docs/reference/error-codes.md");
writeFileSync(target, renderErrorCodesMarkdown(), "utf8");
console.log(`Wrote ${target}`);
