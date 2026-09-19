/// The generator's `$EVENT<n>` numbering: each uuidv7 event id is replaced by
/// a placeholder numbered in order of first appearance, and a later step's
/// argv turns placeholders back into this run's own ids.
struct EvidenceEventNumbering {
  private(set) var identifiers: [String] = []

  static var eventIdentifier: Regex<Substring> {
    #/[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}/#
  }

  /// `text` with every id numbered, first sightings taking the next number.
  mutating func numbered(_ text: String) -> String {
    var seen = identifiers
    let result = text.replacing(Self.eventIdentifier) { match in
      let identifier = String(match.output)
      if let index = seen.firstIndex(of: identifier) {
        return "$EVENT\(index + 1)"
      }
      seen.append(identifier)
      return "$EVENT\(seen.count)"
    }
    identifiers = seen
    return result
  }

  /// `text` with every bound placeholder replaced by its id, highest number
  /// first so `$EVENT1` never eats the front of `$EVENT10`.
  func concrete(_ text: String) -> String {
    identifiers.enumerated().reversed().reduce(text) { partial, entry in
      partial.replacingOccurrences(of: "$EVENT\(entry.offset + 1)", with: entry.element)
    }
  }
}
