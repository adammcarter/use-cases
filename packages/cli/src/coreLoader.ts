// Core loader for the CLI. Reaches @use-cases-plugin/core through a bundled-dist
// fallback so a not-yet-built core surfaces a friendly hint instead of a raw
// ERR_MODULE_NOT_FOUND. BOTH the builtins dispatcher and the registry runtime
// load core through here — a static `import … from "@use-cases-plugin/core"` in a
// command module would bypass the diagnostics.contracts.missing_build_hint handler
// below. Owning the loader here (rather than in builtins.ts) keeps the dependency
// graph honest: runtime → coreLoader and builtins → coreLoader, not runtime →
// builtins.
type UcmCoreModule = typeof import("@use-cases-plugin/core");

export const MISSING_BUILD_MESSAGE =
  "ucp: the compiled core is missing. Run `pnpm build` from the repository root before using the CLI.";

export function isMissingCoreModule(error: unknown): boolean {
  return (
    error instanceof Error && "code" in error && (error as { code?: unknown }).code === "ERR_MODULE_NOT_FOUND"
  );
}

function isMissingCorePackage(error: unknown): boolean {
  return isMissingCoreModule(error) && error instanceof Error && error.message.includes("@use-cases-plugin/core");
}

export async function loadUcmCore(): Promise<UcmCoreModule> {
  try {
    return await import("@use-cases-plugin/core");
  } catch (error) {
    if (!isMissingCorePackage(error)) {
      throw error;
    }
    const bundledCoreSpecifier = "../../core/dist/index.js";
    try {
      return (await import(bundledCoreSpecifier)) as UcmCoreModule;
    } catch (fallbackError) {
      // The package alias AND the bundled dist both failed to resolve: the
      // compiled core/dist has not been built yet. Surface an actionable hint
      // instead of letting a raw ERR_MODULE_NOT_FOUND stack reach the user.
//: @use-case: diagnostics.contracts.missing_build_hint
      if (isMissingCoreModule(fallbackError)) {
        process.stderr.write(`${MISSING_BUILD_MESSAGE}\n`);
        process.exit(2);
      }
//: @use-case: end diagnostics.contracts.missing_build_hint
      throw fallbackError;
    }
  }
}
