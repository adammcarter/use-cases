import { existsSync, lstatSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { extname, isAbsolute, join, relative, sep } from "node:path";
import { TextDecoder } from "node:util";
import type { Diagnostic } from "../schema/index.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import type { EvidenceEvent, EvidenceLedgerResult } from "./types.js";

export type ReadEvidenceLedgerResult = {
  ledgers: EvidenceLedgerResult[];
  events: EvidenceEvent[];
  diagnostics: Diagnostic[];
};

export function evidenceRoot(context: ResolvedWorkspaceContext): string {
  return join(context.data_root, "evidence");
}

export function evidenceRelativePath(context: ResolvedWorkspaceContext, path: string): string {
  return relative(context.data_root, path).split(sep).join("/");
}

export function readEvidenceLedgers(context: ResolvedWorkspaceContext): ReadEvidenceLedgerResult {
  const root = evidenceRoot(context);
  if (!existsSync(root)) {
    return { ledgers: [], events: [], diagnostics: [] };
  }

  const rootReal = realpathSync(root);
  const ledgerPaths = listJsonlFiles(root, rootReal).sort();
  const ledgers: EvidenceLedgerResult[] = [];
  const events: EvidenceEvent[] = [];
  const diagnostics: Diagnostic[] = [];

  for (const path of ledgerPaths) {
    const relPath = evidenceRelativePath(context, path);
    const read = readLedgerFile(path, relPath);
    ledgers.push(read.ledger);
    events.push(...read.events);
    diagnostics.push(...read.diagnostics);
  }

  return { ledgers, events, diagnostics };
}

function listJsonlFiles(root: string, rootReal: string): string[] {
  const results: string[] = [];
  for (const entry of readdirSync(root, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name))) {
    const fullPath = join(root, entry.name);
    const stat = lstatSync(fullPath);
    if (stat.isSymbolicLink()) {
      continue;
    }
    if (stat.isDirectory()) {
      results.push(...listJsonlFiles(fullPath, rootReal));
      continue;
    }
    if (!stat.isFile() || extname(fullPath) !== ".jsonl") {
      continue;
    }
    const realPath = realpathSync(fullPath);
    const rel = relative(rootReal, realPath);
    if (rel === "" || (!rel.startsWith("..") && !isAbsolute(rel))) {
      results.push(fullPath);
    }
  }
  return results;
}

//: @use-case: evidence.ledger.damaged_ledger_replay
function readLedgerFile(path: string, relPath: string): {
  ledger: EvidenceLedgerResult;
  events: EvidenceEvent[];
  diagnostics: Diagnostic[];
} {
  const bytes = readFileSync(path);
  const source = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  const normalized = source.replaceAll("\r\n", "\n");
  const endsWithNewline = normalized.endsWith("\n");
  const rawLines = normalized.split("\n");
  if (endsWithNewline) {
    rawLines.pop();
  }

  const diagnostics: Diagnostic[] = [];
  const events: EvidenceEvent[] = [];
  let tornTail = false;
  let unknownScopeDamage = false;

  for (const [index, line] of rawLines.entries()) {
    const lineNumber = index + 1;
    if (line.trim() === "") {
      continue;
    }
    if (!endsWithNewline && index === rawLines.length - 1) {
      tornTail = true;
      diagnostics.push(diagnostic("evidence_torn_tail", "Evidence ledger has an unterminated final line.", `${relPath}:${lineNumber}`));
      continue;
    }
    if (hasDuplicateJsonKeys(line)) {
      unknownScopeDamage = true;
      diagnostics.push(diagnostic("evidence_parse_error", "Duplicate JSON keys are not allowed.", `${relPath}:${lineNumber}`));
      continue;
    }
    try {
      const value = JSON.parse(line) as EvidenceEvent;
      events.push(value);
    } catch (error) {
      unknownScopeDamage = true;
      diagnostics.push(diagnostic("evidence_parse_error", error instanceof Error ? error.message : String(error), `${relPath}:${lineNumber}`));
    }
  }

  return {
    ledger: {
      path: relPath,
      complete: !tornTail && !unknownScopeDamage,
      events_loaded: events.length,
      torn_tail: tornTail,
      unknown_scope_damage: unknownScopeDamage
    },
    events,
    diagnostics
  };
}
//: @use-case: end evidence.ledger.damaged_ledger_replay

function hasDuplicateJsonKeys(source: string): boolean {
  const stack: Array<Set<string>> = [];
  let inString = false;
  let escaped = false;
  let token = "";
  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === "\"") {
        inString = false;
        const rest = source.slice(index + 1).trimStart();
        if (rest.startsWith(":") && stack.length > 0) {
          const keys = stack[stack.length - 1];
          if (keys.has(token)) {
            return true;
          }
          keys.add(token);
        }
        token = "";
      } else {
        token += char;
      }
      continue;
    }
    if (char === "\"") {
      inString = true;
      token = "";
    } else if (char === "{") {
      stack.push(new Set());
    } else if (char === "}") {
      stack.pop();
    }
  }
  return false;
}

export function diagnostic(code: string, message: string, sourcePath: string | null, entityId: string | null = null): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath,
    json_pointer: null,
    entity_id: entityId,
    related_ids: []
  };
}
