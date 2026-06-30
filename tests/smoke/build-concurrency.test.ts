import { spawn } from "node:child_process";
import { once } from "node:events";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");

describe("build artifact generation", () => {
  test("schema copying is safe when builds overlap", async () => {
    const results = await Promise.all(
      Array.from({ length: 32 }, (_, index) => runCopySchemas(index))
    );

    const failures = results.filter((result) => result.code !== 0);
    expect(failures).toEqual([]);
  }, 30_000);
});

async function runCopySchemas(index: number) {
  const child = spawn(
    process.execPath,
    ["packages/core/scripts/copy-schemas.mjs"],
    {
      cwd: repoRoot,
      stdio: ["ignore", "pipe", "pipe"]
    }
  );
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk: string) => {
    stderr += chunk;
  });
  const [code] = (await once(child, "exit")) as [number | null];
  return { index, code, stderr };
}
