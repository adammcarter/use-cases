import { createHash } from "node:crypto";

// Deterministic JSON canonicalization for hashing.
//
// Rules:
//   - object keys sorted by UTF-16 code unit (stable across hosts)
//   - array order is preserved exactly as given (the caller decides ordering)
//   - keys whose value is `undefined` are dropped (JSON has no undefined)
//   - no insignificant whitespace
//   - non-finite numbers are rejected (they cannot round-trip through JSON)
export function canonicalJson(value: unknown): string {
  return serialize(value);
}

function serialize(value: unknown): string {
  if (value === null) {
    return "null";
  }
  const type = typeof value;
  if (type === "number") {
    if (!Number.isFinite(value as number)) {
      throw new Error("canonical_json: non-finite numbers are not serializable");
    }
    return JSON.stringify(value);
  }
  if (type === "boolean" || type === "string") {
    return JSON.stringify(value);
  }
  if (type === "bigint") {
    throw new Error("canonical_json: bigint is not serializable");
  }
  if (type !== "object") {
    throw new Error(`canonical_json: unsupported value type: ${type}`);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => serialize(item)).join(",")}]`;
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, item]) => item !== undefined)
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0));
  return `{${entries
    .map(([key, item]) => `${JSON.stringify(key)}:${serialize(item)}`)
    .join(",")}}`;
}

// sha256 of UTF-8 string bytes or raw bytes, returned as "sha256:<hex>".
export function sha256(input: string | Uint8Array): string {
  return `sha256:${createHash("sha256").update(input).digest("hex")}`;
}

// Convenience: canonicalize a value then hash it.
export function canonicalJsonSha256(value: unknown): string {
  return sha256(canonicalJson(value));
}
