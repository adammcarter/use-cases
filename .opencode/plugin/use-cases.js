// OpenCode plugin for the use-cases.
//
// OpenCode exposes a native JS/TS plugin system rather than the command-hook
// model the other hosts use, so delivery here is Shape B: inject the trusted
// bootstrap through the current message-transform hook, while keeping
// `session.started` for compatibility with older OpenCode plugin contracts.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
// .opencode/plugin/use-cases.js -> repo root is two levels up.
const pluginRoot = resolve(here, "../..");
const marker = "<EXTREMELY_IMPORTANT>";

let bootstrapCache;

function readBootstrap() {
  if (bootstrapCache !== undefined) return bootstrapCache;

  try {
    const text = readFileSync(resolve(pluginRoot, "bootstrap/use-cases.md"), "utf8").trimEnd();
    bootstrapCache = text.includes(marker)
      ? text
      : `<EXTREMELY_IMPORTANT>\n${text}\n</EXTREMELY_IMPORTANT>`;
  } catch {
    bootstrapCache = "<EXTREMELY_IMPORTANT>\nError reading use-cases bootstrap\n</EXTREMELY_IMPORTANT>";
  }

  return bootstrapCache;
}

function injectBootstrap(output) {
  const messages = Array.isArray(output?.messages) ? output.messages : [];
  const firstUser = messages.find((message) => message?.info?.role === "user");
  if (!firstUser) return;

  firstUser.parts = Array.isArray(firstUser.parts) ? firstUser.parts : [];
  if (firstUser.parts.some((part) => part?.type === "text" && part?.text?.includes(marker))) return;

  const ref = firstUser.parts[0] ?? { type: "text", text: "" };
  firstUser.parts.unshift({ ...ref, type: "text", text: readBootstrap() });
}

export const UseCasesPlugin = async () => {
  const bootstrap = readBootstrap();
  return {
    "session.started": async () => ({ context: bootstrap }),
    "experimental.chat.messages.transform": async (_input, output) => {
      injectBootstrap(output);
    }
  };
};

export default UseCasesPlugin;
