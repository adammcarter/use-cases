/// The eight read-only resources (packages/mcp/src/resources.ts).
///
/// Each reuses the same read-only core the CLI wraps and returns the SAME
/// structured JSON. A resource NEVER mutates, runs a verifier or mints a proof
/// — which is what makes them usable with no write gate at all.
public enum McpResourceCatalog {
  public static let jsonMimeType = "application/json"

  public static let descriptors: [McpResourceDescriptor] = [
    McpResourceDescriptor(
      uri: "uc://matrix",
      name: "Use cases",
      description: "Matrix validation result plus the full list of use cases (read-only). "
        + "Add ?repo=<path> or configure UCM_MCP_REPO.",
    ),
    McpResourceDescriptor(
      uri: "uc://matrix/status",
      name: "Matrix + evidence status",
      description: "Combined matrix validation and evidence assurance status (read-only).",
    ),
    McpResourceDescriptor(
      uri: "uc://freshness",
      name: "Marker freshness status",
      description: "Read-only freshness scan (marker bindings vs proofs) — the same status "
        + "`uc scan` emits. Never runs verifiers.",
    ),
    McpResourceDescriptor(
      uri: "uc://bindings",
      name: "Marker binding registry",
      description: "The materialized append-only binding registry "
        + "(row id -> binding slugs), read-only.",
    ),
    McpResourceDescriptor(
      uri: "uc://ledger",
      name: "Proof ledger validation",
      description: "Read-only validate-ledger summary: evidence/registry integrity, "
        + "append-only discipline, and hash-chain status.",
    ),
    McpResourceDescriptor(
      uri: "uc://evidence",
      name: "Evidence assurance status",
      description: "Replayed evidence assurance status for the matrix (read-only).",
    ),
    McpResourceDescriptor(
      uri: "uc://schemas",
      name: "Public schema index",
      description: "Index of public Use Cases JSON schemas. Read an individual schema at "
        + "uc://schemas/{name} (e.g. uc://schemas/common.schema.json). No repo required.",
    ),
    McpResourceDescriptor(
      uri: "uc://config",
      name: "Resolved workspace config",
      description: "Resolved workspace roots and config provenance for a repo (read-only).",
    ),
  ]
}
