// The public PRODUCT identity (shown by `--version`, MCP serverInfo, npm package).
// Renamed to Use Cases Plugin for public v1.
export const PRODUCT_NAME = "use-cases-plugin";
export const UCP_VERSION = "1.0.0";

// The DEFAULT workspace component id used when a repo's config does not set one.
// This is matrix DATA (it appears in this repo's rows, bindings, proofs, and many
// fixtures), distinct from the product name above. Migrated to the new identity
// during the dogfood/re-prove phase: the self-matrix is regenerated under this id
// and re-proven, so no previously valid signed proof is silently carried over.
export const DEFAULT_COMPONENT_ID = "use-cases-plugin";

export type VersionInfo = {
  name: typeof PRODUCT_NAME;
  version: typeof UCP_VERSION;
};

export function getVersionInfo(): VersionInfo {
  return {
    name: PRODUCT_NAME,
    version: UCP_VERSION
  };
}
