// Acceptance test for use-case row
//   presentation_skills.evidence.crash_durable_ledger_writes
//
// This is the default verifier target for that row: the row's resolved `script`
// verifier runs THIS file (see use-cases/presentation-skills/evidence.yml). It
// exercises the REAL durable-write primitive in
// packages/ucm-core/src/durableWrite.ts and asserts the two observable outcomes
// the row promises:
//
//   1. Atomic append — appending an event through the open/write/fsync/close
//      pattern the JSONL ledgers use leaves the ledger holding the WHOLE event or
//      none of it, never a half-written / truncated line.
//   2. Best-effort durability — when a filesystem cannot fsync a temp file
//      (EIO/EINVAL/ENOSYS/ENOTSUP), the write degrades to best-effort instead of
//      throwing; any OTHER failure, or the same failure OUTSIDE the temp root,
//      still propagates so real corruption is never silently swallowed.
//
// fsync failure is injected by mocking ONLY `fsyncSync` on node:fs (everything
// else — realpathSync, openSync, writeSync … — stays real), which is the only
// deterministic, cross-platform way to simulate "this filesystem can't fsync".
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  closeSync,
  mkdtempSync,
  openSync,
  readFileSync,
  rmSync,
  writeSync
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// A controllable fsync fault, toggled per-test. Hoisted so the vi.mock factory
// (which is itself hoisted above the imports) can close over it.
const fsyncFault = vi.hoisted(() => ({ error: null as NodeJS.ErrnoException | null }));

vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return {
    ...actual,
    // Pass through to the real fsync unless a test has armed a fault.
    fsyncSync: (fd: number): void => {
      if (fsyncFault.error) {
        throw fsyncFault.error;
      }
      actual.fsyncSync(fd);
    }
  };
});

// Imported AFTER the mock is declared so durableWrite binds the mocked fsyncSync.
const { fsyncBestEffortForTemp } = await import(
  "../../packages/ucm-core/src/durableWrite.js"
);

function errnoError(code: string): NodeJS.ErrnoException {
  const error = new Error(`${code}: injected fsync failure`) as NodeJS.ErrnoException;
  error.code = code;
  return error;
}

// Replicates the open("a") / write(line + "\n") / fsync / close append the JSONL
// ledgers (appendEvidenceEvent, appendShowcaseEventLine) perform.
function appendLine(ledgerPath: string, record: unknown): void {
  const fd = openSync(ledgerPath, "a");
  try {
    writeSync(fd, `${JSON.stringify(record)}\n`);
    fsyncBestEffortForTemp(fd, ledgerPath);
  } finally {
    closeSync(fd);
  }
}

describe("crash_durable_ledger_writes", () => {
  let dir: string;

  beforeEach(() => {
    fsyncFault.error = null;
    dir = mkdtempSync(join(tmpdir(), "ucp-durable-"));
  });

  afterEach(() => {
    fsyncFault.error = null;
    rmSync(dir, { recursive: true, force: true });
  });

  test("atomic append: each event is a whole line, never a partial one", () => {
    const ledger = join(dir, "events.jsonl");
    const events = [
      { seq: 1, kind: "evidence_recorded" },
      { seq: 2, kind: "evidence_recorded" },
      { seq: 3, kind: "evidence_recorded" }
    ];

    for (const event of events) {
      appendLine(ledger, event);
    }

    const raw = readFileSync(ledger, "utf8");
    // The ledger ends on a newline -> no dangling partial last line.
    expect(raw.endsWith("\n")).toBe(true);
    const lines = raw.split("\n").filter((line) => line.length > 0);
    expect(lines).toHaveLength(events.length);
    // Every line parses fully (whole-or-nothing) and round-trips.
    expect(lines.map((line) => JSON.parse(line))).toEqual(events);
  });

  test("best-effort durability: an unsupported temp-file fsync degrades, not throws", () => {
    const ledger = join(dir, "events.jsonl");
    for (const code of ["EIO", "EINVAL", "ENOSYS", "ENOTSUP"]) {
      fsyncFault.error = errnoError(code);
      // The append still completes; the line is durably written even though the
      // platform refused to fsync the temp file.
      expect(() => appendLine(ledger, { code })).not.toThrow();
    }
    const lines = readFileSync(ledger, "utf8").split("\n").filter((l) => l.length > 0);
    expect(lines.map((line) => JSON.parse(line))).toEqual([
      { code: "EIO" },
      { code: "EINVAL" },
      { code: "ENOSYS" },
      { code: "ENOTSUP" }
    ]);
  });

  test("a non-degradable fsync failure still propagates (no silent corruption)", () => {
    const ledger = join(dir, "events.jsonl");
    const fd = openSync(ledger, "a");
    try {
      // EACCES is not a best-effort temp code -> must surface, never be swallowed.
      fsyncFault.error = errnoError("EACCES");
      expect(() => fsyncBestEffortForTemp(fd, ledger)).toThrow(/EACCES/);
    } finally {
      fsyncFault.error = null;
      closeSync(fd);
    }
  });

  test("a best-effort code OUTSIDE the temp root still propagates", () => {
    // Same EIO code, but a path that is NOT inside the OS temp root: the
    // best-effort degrade must not apply, so the error surfaces.
    const fd = openSync(join(dir, "events.jsonl"), "a");
    try {
      fsyncFault.error = errnoError("EIO");
      expect(() => fsyncBestEffortForTemp(fd, "/not/a/temp/path/events.jsonl")).toThrow(
        /EIO/
      );
    } finally {
      fsyncFault.error = null;
      closeSync(fd);
    }
  });
});
