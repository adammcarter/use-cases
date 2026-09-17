/// What the showcase- and approve-run corpus comparison replaces, and why each
/// value cannot be compared as recorded.
///
/// Every appending verb in the corpus pins `--idempotency-key`, so run ids
/// (`run.<key>`), event ids (`evt.run.<key>.<n>`), sequences, plan content
/// hashes, ledger head hashes, evidence digests, approval states, assurance
/// tiers and capture methods are all compared byte for byte. What is masked,
/// on BOTH sides:
///
/// - **the body of every PEM.** Each case mints its own ed25519 pair, as
///   `tests/blackbox/showcase-flow.test.ts` does, so no private key lands in
///   the repository (row 4c precedent). Both the file form and the
///   JSON-escaped form inside a keyring are masked;
/// - **every signature value**, for the same reason: a different key signs on
///   each side;
/// - **the `approval.<uuid>` nonce** a minted approval request carries
///   (`jti`, and the `nonce` line of the human rendering), and the `iat`,
///   `exp` and `created_at` stamps beside it, which come from the wall clock;
/// - **the `intent_digest` of an `approval_recorded`, `approval_rejected` or
///   `approval_nonce_burned` event.** Those intents carry the token, so the
///   digest covers the nonce and the signature. Every other event's digest is
///   compared, including a verdict's and a finish's;
/// - **every other millisecond ISO timestamp** than the ones the corpus pins
///   (`2026-06-25T12:…`, and the envelope's own `1970-01-01T00:00:00.000Z`):
///   a `record-observation` without `--recorded-at` stamps the wall clock;
/// - **a parser's own wording**, as in the earlier corpora.
///
/// Each pattern lives inside the step that applies it: a regex literal written
/// as a computed property reads to the `single_line_closure_body` rule as a
/// closure doing something on one line.
enum ShowcaseCommandsMasking {
  static let pinnedTimestampPrefix = "2026-06-25T12:"
  static let pinnedTimestamps: Set = ["1970-01-01T00:00:00.000Z"]

  static func masked(_ text: String) -> String {
    var masked = maskedParserWording(text)
    masked = maskedNonces(masked)
    masked = maskedKeyMaterial(masked)
    masked = maskedApprovalDigests(masked)
    masked = maskedTimestamps(masked)
    return maskedApprovalDigestsInText(masked)
  }

  /// The `yaml` package's and V8's own wording, after a frozen prefix. An
  /// errno tail (`ENOENT`, `EISDIR`, `EACCES` — node's own text, which
  /// `NodeFile` reproduces) is compared.
  private static func maskedParserWording(_ text: String) -> String {
    var masked = text
    let diagnostic = #/("code":"(?:evidence_)?parse_error",[^{}]*?"message":")(?:[^"\\]|\\.)*/#
    let planFile = #/(Presentation plan file could not be read: )(?!E[A-Z]+:)(?:[^"\\]|\\.)*/#
    let flag = #/(could not read\/parse --[a-z-]+: )(?!E[A-Z]+:)(?:[^"\\]|\\.)*/#
    masked = masked.replacing(diagnostic) { match in
      match.output.1 + "<parser message>"
    }
    masked = masked.replacing(planFile) { match in
      match.output.1 + "<parser message>"
    }
    return masked.replacing(flag) { match in
      match.output.1 + "<parser message>"
    }
  }

  /// A minted approval request's nonce, wherever it appears: the `jti` of the
  /// request and the token, the `nonce` line of the human rendering, and the
  /// burn event that spends it.
  private static func maskedNonces(_ text: String) -> String {
    let nonce = #/approval\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/#
    return text.replacing(nonce) { _ in
      "approval.<nonce>"
    }
  }

  /// Every PEM body and every signature. A PEM is base64 lines each ended by a
  /// newline that is real (a key file) or escaped (a keyring's JSON string),
  /// and the separator is kept so only the key's own bytes are replaced.
  private static func maskedKeyMaterial(_ text: String) -> String {
    let pem = #/(-----BEGIN [A-Z ]+KEY-----(?:\n|\\n))(?:[A-Za-z0-9+/=]+(?:\n|\\n))+/#
    let json = #/("value":\s*")[A-Za-z0-9+/=]{40,}"/#
    let human = #/value: [A-Za-z0-9+/=]{40,}/#
    var masked = text.replacing(pem) { match in
      let header = String(match.output.1)
      return header + "<pem>" + (header.hasSuffix("\\n") ? "\\n" : "\n")
    }
    masked = masked.replacing(json) { match in
      match.output.1 + "<signature>\""
    }
    return masked.replacing(human) { _ in
      "value: <signature>"
    }
  }

  /// An approval event's intent covers the token, so its digest covers the
  /// nonce and the signature. `approval_recorded`, `approval_rejected` and
  /// `approval_nonce_burned` are the only `approval_` event types.
  private static func maskedApprovalDigests(_ text: String) -> String {
    let event = #/("event_type":"approval_[a-z_]+",[^{}]*?"intent_digest":")sha256:[0-9a-f]{64}/#
    return text.replacing(event) { match in
      match.output.1 + "<approval digest>"
    }
  }

  private static func maskedTimestamps(_ text: String) -> String {
    let stamp = #/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z/#
    return text.replacing(stamp) { match in
      let value = String(match.output)
      let isPinned = pinnedTimestamps.contains(value)
        || value.hasPrefix(pinnedTimestampPrefix)
      return isPinned ? value : "<timestamp>"
    }
  }

  /// The human rendering puts each member on its own line, so an approval's
  /// digest is found by walking them: the first `intent_digest` after an
  /// approval `event_type` line belongs to that event, and the next
  /// `event_type` line ends the block (the row 4d void-digest precedent).
  private static func maskedApprovalDigestsInText(_ text: String) -> String {
    var isApproval = false
    let digest = #/^(\s*intent_digest: )sha256:[0-9a-f]{64}$/#
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line -> String in
        if line.contains("event_type: ") {
          isApproval = line.contains("event_type: approval_")
          return String(line)
        }
        guard isApproval, let match = line.firstMatch(of: digest) else {
          return String(line)
        }
        isApproval = false
        return match.output.1 + "<approval digest>"
      }
    return lines.joined(separator: "\n")
  }
}
