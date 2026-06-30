import { fsyncSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { isAbsolute, relative, resolve } from "node:path";

const BEST_EFFORT_TEMP_SYNC_CODES = new Set(["EIO", "EINVAL", "ENOSYS", "ENOTSUP"]);

//: @use-case: evidence.ledger.crash_durable_ledger_writes
export function fsyncBestEffortForTemp(fd: number, path: string): void {
  try {
    fsyncSync(fd);
  } catch (error) {
    if (isBestEffortTempSyncError(error, path)) {
      return;
    }
    throw error;
  }
}
//: @use-case: end evidence.ledger.crash_durable_ledger_writes

function isBestEffortTempSyncError(error: unknown, path: string): boolean {
  const code = (error as NodeJS.ErrnoException).code;
  return typeof code === "string" && BEST_EFFORT_TEMP_SYNC_CODES.has(code) && isInsideTempRoot(path);
}

function isInsideTempRoot(path: string): boolean {
  const rel = relative(realPathOrResolved(tmpdir()), realPathOrResolved(path));
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

function realPathOrResolved(path: string): string {
  try {
    return realpathSync(path);
  } catch {
    return resolve(path);
  }
}
