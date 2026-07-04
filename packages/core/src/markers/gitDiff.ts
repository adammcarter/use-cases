// Read-only git-diff plumbing for `uc impact` (0.2.0).
//
// This module answers a single question — "which files changed, and which NEW
// line ranges did the change add/modify?" — by parsing `git diff` output. It is
// deliberately SEPARATE from the freshness/trust engine: impact is an advisory
// lens, never a verdict. The only impure piece is the injected `GitRunner`
// (shared with appendOnly.ts), so the parsing is pure and unit-testable and the
// end-to-end path is exercised against a real repo in the CLI suite.
//
// Comparison modes (mirroring the CLI flags):
//   default            -> `git diff HEAD`          (uncommitted working tree vs HEAD)
//   { staged: true }   -> `git diff --cached HEAD` (the index vs HEAD)
//   { base: "<ref>" }  -> `git diff <ref>`         (working tree vs a ref)
import { execFileSync } from "node:child_process";
import type { GitRunner } from "./appendOnly.js";

// A 1-based inclusive line range (both the binding span and a diff hunk use it).
export interface LineRange {
  start_line: number;
  end_line: number;
}

// One classified entry from `git diff --name-status -M -z`. `renamed`/copies carry
// the source path in `old_file`; a plain add/modify/delete has `old_file: null`.
export type ChangeKind = "added" | "modified" | "deleted" | "renamed";

export interface GitDiffChange {
  change: ChangeKind;
  file: string; // the destination (current) path
  old_file: string | null; // the source path for a rename/copy, else null
}

// A changed file plus the NEW-side line ranges its hunks added/modified. A
// deleted file (or a rename with no content hunks) carries an empty `ranges`.
export interface ChangedFile extends GitDiffChange {
  ranges: LineRange[];
}

export interface CollectChangedFilesOptions {
  runner?: GitRunner;
  cwd?: string;
  // Compare the working tree against this ref instead of HEAD.
  base?: string;
  // Compare the index (staged) against HEAD instead of the working tree.
  staged?: boolean;
}

export interface CollectedDiff {
  // The human-facing base label ("HEAD", the ref, or "HEAD (staged)").
  base: string;
  files: ChangedFile[];
}

const defaultRunner: GitRunner = (args, cwd) =>
  execFileSync("git", args, { cwd, encoding: "utf8" });

// True iff two inclusive line ranges intersect at all.
export function rangesOverlap(a: LineRange, b: LineRange): boolean {
  return a.start_line <= b.end_line && b.start_line <= a.end_line;
}

// Parse `git diff --name-status -M -z` output. The `-z` framing is NUL-separated
// fields: for M/A/D it is `status\0path`; for R/C it is `status\0old\0new`. A
// copy (C) is reported as a plain add of the destination (its old content is
// untouched), while a rename (R) is surfaced as `renamed` so the caller can flag
// a binding whose marked code moved away.
export function parseNameStatusZ(text: string): GitDiffChange[] {
  const fields = text.split("\0").filter((field) => field.length > 0);
  const changes: GitDiffChange[] = [];
  let i = 0;
  while (i < fields.length) {
    const status = fields[i];
    const code = status[0];
    if (code === "R" || code === "C") {
      const oldFile = fields[i + 1];
      const newFile = fields[i + 2];
      i += 3;
      if (oldFile === undefined || newFile === undefined) {
        break; // malformed tail; stop rather than emit a partial entry
      }
      changes.push({
        change: code === "R" ? "renamed" : "added",
        file: newFile,
        old_file: oldFile
      });
      continue;
    }
    const file = fields[i + 1];
    i += 2;
    if (file === undefined) {
      break;
    }
    const change: ChangeKind = code === "A" ? "added" : code === "D" ? "deleted" : "modified";
    changes.push({ change, file, old_file: null });
  }
  return changes;
}

// A `@@ -old +new @@` hunk header. We only care about the NEW-side range (the
// lines that now exist after the change) since impact asks "what does my current
// code touch". `unified=0` gives one header per contiguous change with no
// context lines, so the header ranges ARE the changed ranges.
const HUNK_HEADER = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/;

// Parse the NEW-side line ranges from a `git diff --unified=0` body. A hunk whose
// new count is 0 (a pure deletion) adds no new-side line and is skipped.
export function parseUnifiedZeroHunks(diff: string): LineRange[] {
  const ranges: LineRange[] = [];
  for (const line of diff.split("\n")) {
    const match = HUNK_HEADER.exec(line);
    if (!match) {
      continue;
    }
    const start = Number.parseInt(match[1], 10);
    const count = match[2] === undefined ? 1 : Number.parseInt(match[2], 10);
    if (count === 0) {
      continue; // pure deletion: no new-side range to flag
    }
    ranges.push({ start_line: start, end_line: start + count - 1 });
  }
  return ranges;
}

// Build the `git diff` argv prefix for the requested comparison mode. `--staged`
// wins its own path (index vs HEAD); otherwise we diff the working tree against
// the base ref (default HEAD).
function diffArgsPrefix(options: CollectChangedFilesOptions): { args: string[]; base: string } {
  if (options.staged) {
    return { args: ["diff", "--cached", "HEAD"], base: "HEAD (staged)" };
  }
  const base = options.base ?? "HEAD";
  return { args: ["diff", base], base };
}

// Collect the changed files (with rename/delete detection) and, for each
// added/modified file, the NEW-side line ranges its hunks touched. Read-only:
// runs only `git diff` (never a mutating git command) via the injected runner.
export function collectChangedFiles(options: CollectChangedFilesOptions): CollectedDiff {
  const runner = options.runner ?? defaultRunner;
  const { args, base } = diffArgsPrefix(options);

  const nameStatus = runner([...args, "--name-status", "-M", "-z"], options.cwd);
  const changes = parseNameStatusZ(nameStatus);

  const files: ChangedFile[] = changes.map((change) => {
    // A deleted file has no NEW side, so it never needs a hunk lookup. Renames
    // and adds/modifies can carry content hunks against the destination path.
    if (change.change === "deleted") {
      return { ...change, ranges: [] };
    }
    const body = runner([...args, "--unified=0", "-M", "--", change.file], options.cwd);
    return { ...change, ranges: parseUnifiedZeroHunks(body) };
  });

  return { base, files };
}
