import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import type { ResolvedWorkspaceContext } from "../roots.js";
import type { ShowcaseEvent } from "./types.js";

export function showcaseRunsRoot(context: ResolvedWorkspaceContext): string {
  return join(context.data_root, "showcase-runs");
}

export function showcaseRunDir(context: ResolvedWorkspaceContext, runId: string): string {
  return join(showcaseRunsRoot(context), runId);
}

export function showcaseLedgerPath(context: ResolvedWorkspaceContext, runId: string): string {
  return join(showcaseRunDir(context, runId), "events.jsonl");
}

export function readShowcaseEvents(context: ResolvedWorkspaceContext, runId: string): {
  complete: boolean;
  events: ShowcaseEvent[];
} {
  const path = showcaseLedgerPath(context, runId);
  if (!existsSync(path)) {
    return { complete: false, events: [] };
  }
  const lines = readFileSync(path, "utf8").split("\n");
  const events: ShowcaseEvent[] = [];
  let complete = true;
  for (const [index, line] of lines.entries()) {
    if (!line.trim()) {
      continue;
    }
    try {
      events.push(JSON.parse(line) as ShowcaseEvent);
    } catch {
      if (index === lines.length - 1) {
        complete = false;
        continue;
      }
      return { complete: false, events };
    }
  }
  return { complete, events };
}

export function appendShowcaseEventLine(context: ResolvedWorkspaceContext, event: ShowcaseEvent): void {
  const path = showcaseLedgerPath(context, event.run_id);
  mkdirSync(dirname(path), { recursive: true });
  const fd = openSync(path, "a");
  try {
    writeSync(fd, `${JSON.stringify(event)}\n`);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
}
