/**
 * Conservative, high-confidence secret redaction shared across the durable
 * ledgers (captured command output, showcase observations, evidence summaries).
 *
 * The patterns are deliberately narrow so legitimate prose is not mangled:
 * a keyword only matches when it is immediately followed by an assignment
 * (`:`/`=`) and a value, and the token patterns require their well-known
 * fixed prefixes plus a minimum length. No broad/greedy patterns.
 */
export function redactSecrets(value: string): string {
  return value
    .replace(/\b(secret|token|password|api[_-]?key)\s*[:=]\s*[^\s]+/gi, (_match, label: string) => `${label}=[redacted]`)
    .replace(/\bsk-[A-Za-z0-9_-]{8,}\b/g, "sk-[redacted]")
    .replace(/\bgh[oprsu]_[A-Za-z0-9]{20,}\b/g, (match) => `${match.slice(0, 4)}[redacted]`)
    .replace(/\bAKIA[0-9A-Z]{16}\b/g, "AKIA[redacted]");
}
