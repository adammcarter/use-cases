// Injectable filesystem seam for the Phase 7 CLI command cores.
//
// The command logic (bind/scan/prove/validate-ledger) is kept pure-ish by routing
// every filesystem touch through `MarkerFs`. The default implementation uses
// node:fs and is what the thin ucm-cli wiring passes; tests run the same default
// against a throwaway tmp dir (or substitute their own seam). Keeping this narrow
// means the command cores never import node:fs directly.
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  writeFileSync
} from "node:fs";
import { dirname } from "node:path";

export interface MarkerDirEntry {
  name: string;
  isDirectory: boolean;
  isFile: boolean;
  isSymlink: boolean;
}

export interface MarkerFs {
  // Read UTF-8 text, or null when the path does not exist.
  readText(path: string): string | null;
  // Write UTF-8 text, creating parent directories. Atomic (temp + rename).
  writeText(path: string, text: string): void;
  exists(path: string): boolean;
  listDir(path: string): MarkerDirEntry[];
}

export const nodeMarkerFs: MarkerFs = {
  readText(path: string): string | null {
    try {
      return readFileSync(path, "utf8");
    } catch (error) {
      if ((error as { code?: string }).code === "ENOENT") {
        return null;
      }
      throw error;
    }
  },
  writeText(path: string, text: string): void {
    mkdirSync(dirname(path), { recursive: true });
    const tempPath = `${path}.tmp-${process.pid}-${Date.now()}`;
    writeFileSync(tempPath, text);
    renameSync(tempPath, path);
  },
  exists(path: string): boolean {
    return existsSync(path);
  },
  listDir(path: string): MarkerDirEntry[] {
    return readdirSync(path, { withFileTypes: true }).map((entry) => ({
      name: entry.name,
      isDirectory: entry.isDirectory(),
      isFile: entry.isFile(),
      isSymlink: entry.isSymbolicLink()
    }));
  }
};

// Append a single JSONL line to a ledger file, tolerating an absent file and a
// missing trailing newline on the existing content. Append-only by construction:
// existing bytes are never rewritten, only extended.
export function appendJsonlLine(fs: MarkerFs, path: string, line: string): void {
  const existing = fs.readText(path) ?? "";
  const base = existing === "" || existing.endsWith("\n") ? existing : `${existing}\n`;
  fs.writeText(path, `${base}${line}\n`);
}
