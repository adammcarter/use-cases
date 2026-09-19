/// What the evidence-command corpus comparison replaces, and why each value
/// cannot be compared as recorded.
///
/// Numbered, not masked (``EvidenceEventNumbering``): every uuidv7 event id,
/// because a later step names it.
///
/// Masked on BOTH sides:
/// - every millisecond ISO timestamp other than the envelope's epoch and the
///   one hand-written ledger lines carry — an append stamps `recorded_at` and
///   `captured_at` with the wall clock, and replay copies `captured_at` into
///   `freshness_inputs`;
/// - the `intent_digest` of an appended `evidence_voided` event: a void's
///   intent names the evidence id as its target, so the digest covers a random
///   id. A recorded event's digest does not, and is compared;
/// - the message of an `evidence_parse_error` diagnostic, which is V8's
///   `JSON.parse` wording (docs/rewrite/ladder-notes.md, rows 3 and 4b). The
///   code, the `source_path` that names the line and everything else are
///   compared.
enum EvidenceCommandsMasking {
  static let pinnedTimestamps: Set = ["1970-01-01T00:00:00.000Z", "2026-09-17T12:00:00.000Z"]
  static let zeroDigest = "sha256:" + String(repeating: "0", count: 64)

  static var timestamp: Regex<Substring> {
    #/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z/#
  }

  static var voidDigestInJSON: Regex<(Substring, Substring)> {
    #/"event_type":"evidence_voided",[^{}]*?"intent_digest":"(sha256:[0-9a-f]{64})/#
  }

  static var digestInText: Regex<(Substring, Substring)> {
    #/intent_digest: (sha256:[0-9a-f]{64})/#
  }

  static var parseErrorMessageInJSON: Regex<(Substring, Substring)> {
    #/("code":"evidence_parse_error","severity":"error","message":")(?:[^"\\]|\\.)*/#
  }

  static var parseErrorMessageInText: Regex<(Substring, Substring)> {
    #/(evidence_parse_error: )[^\n]*/#
  }

  static func masked(_ text: String) -> String {
    let masked = text
      .replacing(parseErrorMessageInJSON) { match in
        match.output.1 + "<parser message>"
      }
      .replacing(parseErrorMessageInText) { match in
        match.output.1 + "<parser message>"
      }
      .replacing(timestamp) { match in
        pinnedTimestamps.contains(String(match.output)) ? String(match.output) : "<timestamp>"
      }
      .replacing(voidDigestInJSON) { match in
        maskedDigest(in: match.output.0, digest: match.output.1)
      }
    return maskedVoidDigestsInText(masked)
  }

  /// The human rendering puts each member on its own line, so a void's digest
  /// is found by walking the lines: the first `intent_digest` after an
  /// `event_type: evidence_voided` line belongs to that void, and the next
  /// `event_type` line ends the block.
  private static func maskedVoidDigestsInText(_ text: String) -> String {
    var isVoid = false
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line -> String in
        if line.contains("event_type: ") {
          isVoid = line.contains("event_type: evidence_voided")
          return String(line)
        }
        guard isVoid, let match = line.firstMatch(of: digestInText) else {
          return String(line)
        }
        isVoid = false
        return maskedDigest(in: line, digest: match.output.1)
      }
    return lines.joined(separator: "\n")
  }

  /// The matched event with its digest replaced, unless the digest is the
  /// all-zero one a hand-written ledger line carries.
  private static func maskedDigest(
    in match: Substring,
    digest: Substring,
  ) -> String {
    guard digest != zeroDigest else {
      return String(match)
    }
    return match.replacingOccurrences(of: digest, with: "<void digest>")
  }
}
