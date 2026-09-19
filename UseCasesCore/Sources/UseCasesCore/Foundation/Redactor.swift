/// Conservative, high-confidence secret redaction shared across the durable
/// ledgers (captured command output, showcase observations, evidence summaries).
///
/// The patterns are deliberately narrow so legitimate prose is not mangled: a
/// keyword only matches when an assignment (`:` or `=`) and a value follow it,
/// and the token patterns require their well-known prefixes plus a minimum
/// length. No broad or greedy patterns.
public enum Redactor {
  private static var assignedKeyword: Regex<(Substring, Substring)> {
    /\b(secret|token|password|api[_-]?key)\s*[:=]\s*\S+/.ignoresCase()
  }

  private static var openAIKey: Regex<Substring> {
    /\bsk-[A-Za-z0-9_\-]{8,}\b/
  }

  private static var githubToken: Regex<Substring> {
    /\bgh[oprsu]_[A-Za-z0-9]{20,}\b/
  }

  private static var awsAccessKeyIdentifier: Regex<Substring> {
    /\bAKIA[0-9A-Z]{16}\b/
  }

  /// Replace high-confidence credential material in `value` with placeholders.
  public static func redactSecrets(_ value: String) -> String {
    var result = value.replacing(assignedKeyword) { match in
      "\(match.output.1)=[redacted]"
    }

    result = result.replacing(openAIKey, with: "sk-[redacted]")

    result = result.replacing(githubToken) { match in
      "\(match.output.prefix(4))[redacted]"
    }

    return result.replacing(awsAccessKeyIdentifier, with: "AKIA[redacted]")
  }
}
