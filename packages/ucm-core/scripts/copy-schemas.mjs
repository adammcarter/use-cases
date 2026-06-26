import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../..");
const source = join(repoRoot, "schemas/v1");
const destination = join(repoRoot, "packages/ucm-core/dist/schemas/v1");
const hostProfileSource = join(repoRoot, "hosts");
const hostProfileDestination = join(repoRoot, "packages/ucm-core/dist/host-profiles");
const lockDir = join(repoRoot, "packages/ucm-core/.copy-schemas.lock");

mkdirSync(dirname(lockDir), { recursive: true });
withDirectoryLock(lockDir, () => {
  mkdirSync(destination, { recursive: true });
  cpSync(source, destination, { recursive: true });
  removeOrphanedEntries(source, destination);
  mkdirSync(hostProfileDestination, { recursive: true });
  cpSync(hostProfileSource, hostProfileDestination, { recursive: true });
  removeOrphanedEntries(hostProfileSource, hostProfileDestination);
});

function withDirectoryLock(path, work) {
  const deadline = Date.now() + 30_000;

  while (true) {
    try {
      mkdirSync(path);
      break;
    } catch (error) {
      if (error?.code !== "EEXIST" || Date.now() >= deadline) {
        throw error;
      }
      sleep(25);
    }
  }

  try {
    work();
  } finally {
    rmSync(path, { recursive: true, force: true });
  }
}

function sleep(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
}

function removeOrphanedEntries(sourceDir, destinationDir) {
  for (const entry of readdirSync(destinationDir, { withFileTypes: true })) {
    const sourcePath = join(sourceDir, entry.name);
    const destinationPath = join(destinationDir, entry.name);
    if (!existsSync(sourcePath)) {
      rmSync(destinationPath, { recursive: true, force: true });
      continue;
    }
    if (entry.isDirectory() && statSync(sourcePath).isDirectory()) {
      removeOrphanedEntries(sourcePath, destinationPath);
    }
  }
}
