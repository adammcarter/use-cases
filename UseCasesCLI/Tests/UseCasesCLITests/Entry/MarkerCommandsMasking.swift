/// What the marker-command corpus comparison replaces on BOTH sides, because it
/// is genuinely nondeterministic or a parser's own wording. Everything else is
/// compared byte for byte.
///
/// - the `event_id` of every registry and proof event (bind, unbind, rebind and
///   prove mint a time-and-random id no flag can pin);
/// - every millisecond ISO timestamp other than the pinned `--generated-at` and
///   the envelope's epoch — the wall-clock `created_at` of registry events and
///   the timestamps of a run given no `--generated-at`;
/// - a proof event's signature value and a non-zero `previous_entry_hash`, both
///   of which cover the random event id;
/// - where a run key is minted or a record is dated by the wall clock, every
///   run attestation and the minted key itself;
/// - the text after `is not valid JSON: `, which is V8's `JSON.parse` wording
///   (see docs/rewrite/ladder-notes.md, row 4);
/// - for keygen, the freshly minted PEM bodies (applied by the caller).
enum MarkerCommandsMasking {
  enum Format {
    /// Stdout that is a JSON envelope: strings are JSON-escaped.
    case json
    /// Human output and file contents: raw text.
    case text
    case file
  }

  static let pinnedTimestamps: Set = ["2026-09-17T12:00:00.000Z", "1970-01-01T00:00:00.000Z"]

  static var eventIdentifierInJSON: Regex<Substring> {
    #/"event_id":"[0-9A-Z]{26}"/#
  }

  static var eventIdentifierInText: Regex<Substring> {
    #/event_id: [0-9A-Z]{26}/#
  }

  static var timestamp: Regex<Substring> {
    #/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z/#
  }

  static var signatureValue: Regex<Substring> {
    #/"value":"[A-Za-z0-9+\/=]{80,}"/#
  }

  static var previousEntryHash: Regex<(Substring, Substring)> {
    #/"previous_entry_hash":"sha256:([0-9a-f]{64})"/#
  }

  static var runAttestation: Regex<Substring> {
    #/hmac-sha256:[0-9a-f]{64}/#
  }

  static var parserWordingInJSON: Regex<Substring> {
    #/is not valid JSON: (?:[^"\\]|\\.)*/#
  }

  static var parserWordingInText: Regex<Substring> {
    #/is not valid JSON: [^\n]*/#
  }

  static var mintedKeyRaw: Regex<(Substring, Substring)> {
    #/-----BEGIN (PRIVATE|PUBLIC) KEY-----\n[A-Za-z0-9+\/=]+\n-----END [A-Z]+ KEY-----/#
  }

  static var mintedKeyEscaped: Regex<(Substring, Substring)> {
    #/-----BEGIN (PRIVATE|PUBLIC) KEY-----\\n[A-Za-z0-9+\/=]+\\n-----END [A-Z]+ KEY-----/#
  }

  static func masked(
    _ text: String,
    format: Format,
    attestationsVary: Bool,
  ) -> String {
    var result = text
      .replacing(eventIdentifierInJSON, with: #""event_id":"<event id>""#)
      .replacing(eventIdentifierInText, with: "event_id: <event id>")
      .replacing(signatureValue, with: #""value":"<signature>""#)
      .replacing(timestamp) { match in
        pinnedTimestamps.contains(String(match.output)) ? String(match.output) : "<timestamp>"
      }
      .replacing(previousEntryHash) { match in
        match.output.1.allSatisfy { $0 == "0" }
          ? String(match.output.0)
          : #""previous_entry_hash":"<hash>""#
      }
    if attestationsVary {
      result = result.replacing(runAttestation, with: "hmac-sha256:<attestation>")
    }
    switch format {
    case .json:
      result = result.replacing(parserWordingInJSON, with: "is not valid JSON: <parser message>")
    case .text:
      result = result.replacing(parserWordingInText, with: "is not valid JSON: <parser message>")
    case .file:
      break
    }
    return result
  }

  /// keygen's PEM bodies replaced, in raw or JSON-escaped text.
  static func withoutMintedKeys(_ text: String) -> String {
    text
      .replacing(mintedKeyRaw) { match in
        let kind = match.output.1
        return "-----BEGIN \(kind) KEY-----\n<minted>\n-----END \(kind) KEY-----"
      }
      .replacing(mintedKeyEscaped) { match in
        let kind = match.output.1
        return #"-----BEGIN \#(kind) KEY-----\n<minted>\n-----END \#(kind) KEY-----"#
      }
  }
}
