import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

// The exit code of every CLI command must track the FINAL envelope's `ok`, not a
// parallel `data.complete` field. `createCliResult` forces `ok:false` whenever an
// error-severity diagnostic is present — even if the caller passed `ok:true` /
// `complete:true`. `doctor package` used to derive its exit code from
// `data.complete`, so an ok:false envelope could ship with exit 0 (a false green).
//
// We drive that drift scenario directly: stub `inspectPackageArtifact` to return a
// `complete:true` result that nonetheless carries an error-severity diagnostic, and
// assert the command reports the ok:false envelope with a NON-ZERO exit code.
vi.mock("../../src/runtime.js", async () => {
  const actual = await vi.importActual<typeof import("../../src/runtime.js")>("../../src/runtime.js");
  return {
    ...actual,
    inspectPackageArtifact: vi.fn(() => ({
      schema_version: 1 as const,
      // Deliberately inconsistent: complete says "fine" while a hard error is present.
      complete: true,
      inspection_target: { kind: "tarball" as const, path: "/tmp/fake.tgz" },
      package_entries: [],
      required_paths: [],
      manifest_references: [],
      bin_entrypoints: [],
      files_allowlist: [],
      forbidden_paths: [],
      forbidden_text: [],
      diagnostics: [
        {
          code: "package.required_path_missing",
          severity: "error" as const,
          message: "Missing package path 'plugin.json'.",
          source_path: "plugin.json",
          json_pointer: null,
          entity_id: null,
          related_ids: []
        }
      ]
    }))
  };
});

const { doctorPackageCommand } = await import("../../src/commands/doctor.js");

let repoRoot: string;

beforeEach(() => {
  // `resolveContextOrError` guards against a non-existent --repo, so point at a real dir.
  repoRoot = mkdtempSync(join(tmpdir(), "ucm-doctor-package-"));
});

afterEach(() => {
  vi.clearAllMocks();
  try {
    rmSync(repoRoot, { recursive: true, force: true });
  } catch {
    /* ignore */
  }
});

describe("doctor package exit code", () => {
  test("reports a non-zero exit when the envelope is ok:false", () => {
    const result = doctorPackageCommand.handler({
      argv: ["--repo", repoRoot],
      flags: {},
      json: true
    });

    const envelope = result.envelope as { ok: boolean; complete: boolean };
    expect(envelope.ok, "an error-severity diagnostic must force ok:false").toBe(false);
    expect(result.exitCode, "exit code must track the ok:false envelope, not data.complete").not.toBe(0);
  });
});
