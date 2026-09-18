// The seam itself, under test.
//
// Every black-box test in the oracle suite (ADR 0007, ladder row 2) reaches the
// binary through `tests/helpers/uc-binary.ts`. If that indirection silently
// stopped being an indirection — if it ignored UC_BIN, or quietly fell back to
// the Node build when the named binary was missing — the whole suite would keep
// passing while testing the wrong thing, and the Swift port would look green on
// evidence it never produced.
//
// So the seam is pinned here: the default really is the built Node CLI, UC_BIN
// really is honoured, and a UC_BIN that cannot run fails loudly.
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { runUc, runUcJson, ucBinary } from "../helpers/uc-binary";

const tempDirs: string[] = [];

afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

function fakeBinary(body: string): string {
  const dir = mkdtempSync(join(tmpdir(), "uc-fake-bin-"));
  tempDirs.push(dir);
  const path = join(dir, "fake-uc");
  writeFileSync(path, `#!/bin/sh\n${body}\n`);
  chmodSync(path, 0o755);
  return path;
}

describe("the black-box harness", () => {
  test("with UC_BIN unset it drives the built Node CLI and returns a v1 envelope", () => {
    delete process.env.UC_BIN;
    const binary = ucBinary();
    expect(binary.overridden).toBe(false);
    expect(binary.leadingArgs[0]).toMatch(/packages\/cli\/dist\/index\.js$/);

    const { envelope, status } = runUcJson(["version"]);
    expect(status).toBe(0);
    expect(envelope.command).toBe("version");
    expect(envelope.schema_version).toBe(1);
    expect(envelope.ok).toBe(true);
  });

  test("UC_BIN names the binary, so the same suite can run against a Swift build", () => {
    const fake = fakeBinary('echo "{\\"command\\":\\"version\\",\\"ok\\":true,\\"schema_version\\":1,\\"protocol_version\\":1,\\"complete\\":true,\\"data\\":{},\\"diagnostics\\":[],\\"context\\":{}}"');
    process.env.UC_BIN = fake;
    try {
      const binary = ucBinary();
      expect(binary.overridden).toBe(true);
      expect(binary.command).toBe(fake);
      expect(binary.leadingArgs).toEqual([]);

      const { envelope } = runUcJson(["version"]);
      expect(envelope.command).toBe("version");
    } finally {
      delete process.env.UC_BIN;
    }
  });

  test("a nonzero exit is returned, not thrown — refusals are behaviours under test", () => {
    const fake = fakeBinary('echo "{\\"command\\":\\"scan\\",\\"ok\\":false,\\"schema_version\\":1,\\"protocol_version\\":1,\\"complete\\":true,\\"data\\":{},\\"diagnostics\\":[],\\"context\\":{}}"\nexit 4');
    process.env.UC_BIN = fake;
    try {
      const { envelope, status } = runUcJson(["scan"]);
      expect(status).toBe(4);
      expect(envelope.ok).toBe(false);
    } finally {
      delete process.env.UC_BIN;
    }
  });

  test("a UC_BIN that emits nothing parseable fails loudly, naming the command", () => {
    const fake = fakeBinary('echo "not json" >&2\nexit 1');
    process.env.UC_BIN = fake;
    try {
      expect(() => runUcJson(["scan"])).toThrowError(/use-cases scan --json: stdout did not parse as JSON/);
    } finally {
      delete process.env.UC_BIN;
    }
  });

  test("runUc hands back raw stdout for the human output path", () => {
    delete process.env.UC_BIN;
    const result = runUc(["version"]);
    expect(result.status).toBe(0);
    expect(result.stdout.trim()).not.toBe("");
  });
});
