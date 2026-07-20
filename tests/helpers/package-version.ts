import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

// Tests that `pnpm pack` a workspace have to name the resulting tarball, and the
// name embeds the version. Reading it from the root package.json keeps those
// tests working across releases instead of breaking on every version bump.
const rootPackageJson = resolve(import.meta.dirname, "../..", "package.json");

export const PACKAGE_VERSION: string = JSON.parse(
  readFileSync(rootPackageJson, "utf8")
).version;

export function packedTarball(packDir: string, workspace: "core" | "cli" | "mcp"): string {
  return join(packDir, `adammcarter-use-cases-${workspace}-${PACKAGE_VERSION}.tgz`);
}
