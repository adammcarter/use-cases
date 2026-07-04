// Unit tests for the pure git-diff helpers that back `uc impact`. The parsing is
// pure text -> structured data; the git access is an injected GitRunner, so no
// test shells out to a real repo here (an end-to-end real-git test lives in the
// CLI subprocess suite).
import { describe, expect, test } from "vitest";
import {
  parseNameStatusZ,
  parseUnifiedZeroHunks,
  collectChangedFiles,
  rangesOverlap,
  type GitDiffChange
} from "../../src/markers/gitDiff.js";
import type { GitRunner } from "../../src/markers/appendOnly.js";

describe("parseNameStatusZ", () => {
  test("parses modified, added and deleted entries", () => {
    // `git diff --name-status -M -z` emits NUL-separated fields: status\0path\0…
    const text = ["M", "src/a.ts", "A", "src/b.ts", "D", "src/c.ts", ""].join("\0");
    expect(parseNameStatusZ(text)).toEqual<GitDiffChange[]>([
      { change: "modified", file: "src/a.ts", old_file: null },
      { change: "added", file: "src/b.ts", old_file: null },
      { change: "deleted", file: "src/c.ts", old_file: null }
    ]);
  });

  test("parses a rename entry (three NUL fields: Rnnn, old, new)", () => {
    const text = ["R100", "old/path.ts", "new/path.ts", ""].join("\0");
    expect(parseNameStatusZ(text)).toEqual<GitDiffChange[]>([
      { change: "renamed", file: "new/path.ts", old_file: "old/path.ts" }
    ]);
  });

  test("parses a copy entry as a plain add of the destination", () => {
    const text = ["C100", "from.ts", "to.ts", ""].join("\0");
    expect(parseNameStatusZ(text)).toEqual<GitDiffChange[]>([
      { change: "added", file: "to.ts", old_file: "from.ts" }
    ]);
  });

  test("returns [] for empty output", () => {
    expect(parseNameStatusZ("")).toEqual([]);
    expect(parseNameStatusZ("\0")).toEqual([]);
  });
});

describe("parseUnifiedZeroHunks", () => {
  test("reads the NEW-file line ranges from @@ headers", () => {
    // Two hunks: a single-line modify at new line 2, and a 2-line add at 6..7.
    const diff = [
      "diff --git a/f.txt b/f.txt",
      "index b8cb000..c95904c 100644",
      "--- a/f.txt",
      "+++ b/f.txt",
      "@@ -2 +2 @@ l1",
      "-l2",
      "+MOD",
      "@@ -5,0 +6,2 @@ l5",
      "+ADD1",
      "+ADD2"
    ].join("\n");
    expect(parseUnifiedZeroHunks(diff)).toEqual([
      { start_line: 2, end_line: 2 },
      { start_line: 6, end_line: 7 }
    ]);
  });

  test("a pure deletion hunk (new count 0) contributes no added range", () => {
    // `@@ -3,2 +2,0 @@` removes lines; there is no new-side range to flag.
    const diff = ["@@ -3,2 +2,0 @@", "-gone1", "-gone2"].join("\n");
    expect(parseUnifiedZeroHunks(diff)).toEqual([]);
  });

  test("returns [] when there are no hunks", () => {
    expect(parseUnifiedZeroHunks("")).toEqual([]);
    expect(parseUnifiedZeroHunks("diff --git a/x b/x\n")).toEqual([]);
  });
});

describe("rangesOverlap", () => {
  test("true when the binding span intersects a hunk range", () => {
    expect(rangesOverlap({ start_line: 10, end_line: 20 }, { start_line: 15, end_line: 15 })).toBe(true);
    expect(rangesOverlap({ start_line: 10, end_line: 20 }, { start_line: 20, end_line: 25 })).toBe(true);
    expect(rangesOverlap({ start_line: 10, end_line: 20 }, { start_line: 5, end_line: 10 })).toBe(true);
  });

  test("false when the ranges are disjoint", () => {
    expect(rangesOverlap({ start_line: 10, end_line: 20 }, { start_line: 21, end_line: 30 })).toBe(false);
    expect(rangesOverlap({ start_line: 10, end_line: 20 }, { start_line: 1, end_line: 9 })).toBe(false);
  });
});

describe("collectChangedFiles (over an injected GitRunner)", () => {
  test("uses `diff HEAD` by default and attaches hunk ranges to modified/added files", () => {
    const calls: string[][] = [];
    const runner: GitRunner = (args) => {
      calls.push(args);
      if (args.includes("--name-status")) {
        return ["M", "src/a.ts", "D", "src/gone.ts", ""].join("\0");
      }
      // per-file unified=0 hunks
      if (args.includes("src/a.ts")) {
        return "@@ -1 +1 @@\n-old\n+new\n";
      }
      return "";
    };
    const result = collectChangedFiles({ runner, cwd: "/repo" });

    // Default base = HEAD; -M for rename detection; -z for NUL framing.
    expect(calls[0]).toEqual(["diff", "HEAD", "--name-status", "-M", "-z"]);
    expect(result.base).toBe("HEAD");
    expect(result.files).toEqual([
      { change: "modified", file: "src/a.ts", old_file: null, ranges: [{ start_line: 1, end_line: 1 }] },
      // A deleted file gets no hunk lookup and carries an empty range list.
      { change: "deleted", file: "src/gone.ts", old_file: null, ranges: [] }
    ]);
  });

  test("--staged compares the index against HEAD (diff --cached HEAD)", () => {
    const calls: string[][] = [];
    const runner: GitRunner = (args) => {
      calls.push(args);
      return args.includes("--name-status") ? "" : "";
    };
    collectChangedFiles({ runner, cwd: "/repo", staged: true });
    expect(calls[0]).toEqual(["diff", "--cached", "HEAD", "--name-status", "-M", "-z"]);
  });

  test("--base <ref> compares the working tree against that ref", () => {
    const calls: string[][] = [];
    const runner: GitRunner = (args) => {
      calls.push(args);
      return "";
    };
    const result = collectChangedFiles({ runner, cwd: "/repo", base: "main" });
    expect(calls[0]).toEqual(["diff", "main", "--name-status", "-M", "-z"]);
    expect(result.base).toBe("main");
  });
});
