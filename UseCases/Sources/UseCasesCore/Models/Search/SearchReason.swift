/// One place a use case matched.
public struct SearchReason: Equatable, Sendable {
  /// The longest a reason's text is, in characters as a person counts them.
  public static let longestText = 160

  public let field: SearchField

  /// The scenario or route the text is in; `nil` for a field that is not in one.
  public let location: String?

  /// The text, cut to ``longestText`` characters.
  public let text: String

  /// A reason; the text is cut here.
  public init(
    field: SearchField,
    location: String?,
    text: String,
  ) {
    self.field = field
    self.location = location
    self.text = Self.cut(text)
  }

  /// The text up to its first 160 characters, cut between characters a person sees as one and
  /// never past 160 Unicode scalars either, which is how a schema counts.
  static func cut(_ text: String) -> String {
    var kept = ""
    var characters = 0
    var scalars = 0

    for character in text {
      let width = character.unicodeScalars.count

      guard characters < longestText, scalars + width <= longestText else {
        break
      }

      kept.append(character)
      characters += 1
      scalars += width
    }

    return kept
  }
}
