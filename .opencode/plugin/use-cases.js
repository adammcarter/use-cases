// OpenCode plugin for the use-cases.
//
// OpenCode exposes a native JS/TS plugin system rather than the command-hook
// model the other hosts use, so delivery here is Shape B (lifecycle injection):
// on `session.started` we return the trusted bootstrap as context. The bootstrap
// text is the same trusted block the hook-based hosts emit
// (bootstrap/use-cases.md). See critical-info-bootstrap / delivery-shapes.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
// .opencode/plugin/use-cases.js -> repo root is two levels up.
const pluginRoot = resolve(here, "../..");

function readBootstrap() {
  try {
    return readFileSync(resolve(pluginRoot, "bootstrap/use-cases.md"), "utf8");
  } catch {
    return "Error reading use-cases bootstrap";
  }
}

export const UseCasesPlugin = async () => {
  // Cache once; session.started can fire repeatedly.
  const bootstrap = readBootstrap();
  return {
    "session.started": async () => ({ context: bootstrap })
  };
};

export default UseCasesPlugin;
