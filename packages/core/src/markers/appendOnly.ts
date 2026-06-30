// Append-only discipline check for JSONL ledgers (spec amendment 2; 4.3 rules
// 9/10). The core `appendOnly` is pure and line-based: the old content must be an
// unchanged PREFIX of the new content. Any edit, delete, or reorder of an
// existing line is a violation. The only impure piece is the thin git helper that
// reads the base-ref version of a file via `git show <base-ref>:<path>`.
import { execFileSync } from "node:child_process";

export interface AppendOnlyViolation {
  // "edited": an existing line's text changed (a reorder shows up as an edit).
  // "deleted": an existing line is gone because the new content is shorter.
  kind: "edited" | "deleted";
  index: number; // 0-based index into oldLines where the prefix first breaks
  old_line: string;
  new_line: string | null; // null when the line was deleted (new is shorter)
  message: string;
}

export type AppendOnlyResult = { ok: true } | { ok: false; violation: AppendOnlyViolation };

// Pure append-only check: oldLines must equal the leading prefix of newLines.
export function appendOnly(
  oldLines: ReadonlyArray<string>,
  newLines: ReadonlyArray<string>
): AppendOnlyResult {
  for (let i = 0; i < oldLines.length; i += 1) {
    if (i >= newLines.length) {
      return {
        ok: false,
        violation: {
          kind: "deleted",
          index: i,
          old_line: oldLines[i],
          new_line: null,
          message: `existing line ${i + 1} was deleted; the registry is append-only`
        }
      };
    }
    if (newLines[i] !== oldLines[i]) {
      return {
        ok: false,
        violation: {
          kind: "edited",
          index: i,
          old_line: oldLines[i],
          new_line: newLines[i],
          message: `existing line ${i + 1} was edited or reordered; the registry is append-only`
        }
      };
    }
  }
  return { ok: true };
}

// Split JSONL text into content lines, dropping a single trailing newline's empty
// segment. Interior blank lines are preserved so a blank-line edit is not hidden.
export function splitJsonlLines(text: string): string[] {
  if (text === "") {
    return [];
  }
  const lines = text.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") {
    lines.pop();
  }
  return lines;
}

// Injectable git runner for testing the base-ref read without a real repo.
export type GitRunner = (args: string[], cwd?: string) => string;

export interface ReadBaseRefOptions {
  cwd?: string;
  runner?: GitRunner;
}

const defaultRunner: GitRunner = (args, cwd) =>
  execFileSync("git", args, { cwd, encoding: "utf8" });

// Patterns git emits when a path does not exist at the given ref. Treated as
// "old content is empty" (a brand-new file added on this branch).
const ABSENT_AT_BASE = /does not exist in|exists on disk, but not in/i;

// Read the base-ref version of a file (`git show <base-ref>:<path>`). Returns ""
// when the path does not exist at the base ref (a newly added file). Any other
// git failure is rethrown with context. Thin and impure by design.
export function readBaseRefFile(
  baseRef: string,
  path: string,
  options: ReadBaseRefOptions = {}
): string {
  const runner = options.runner ?? defaultRunner;
  try {
    return runner(["show", `${baseRef}:${path}`], options.cwd);
  } catch (error) {
    const stderr = String(
      (error as { stderr?: unknown }).stderr ?? (error as Error).message ?? ""
    );
    if (ABSENT_AT_BASE.test(stderr)) {
      return "";
    }
    throw new Error(`git show ${baseRef}:${path} failed: ${stderr.trim() || "unknown error"}`);
  }
}

// Convenience: check current JSONL text against its base-ref version, splitting
// both into lines first.
export function appendOnlyAgainstBaseRef(
  baseRef: string,
  path: string,
  currentText: string,
  options: ReadBaseRefOptions = {}
): AppendOnlyResult {
  const oldText = readBaseRefFile(baseRef, path, options);
  return appendOnly(splitJsonlLines(oldText), splitJsonlLines(currentText));
}
