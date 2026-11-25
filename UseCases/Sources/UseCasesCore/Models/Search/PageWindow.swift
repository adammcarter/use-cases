/// The part of a list of results one page shows (chapter 16 §15), for `search` and `docs`.
struct PageWindow: Equatable, Sendable {
  static let defaultSize = 20
  static let sizes = 1 ... 100

  /// The size `--page-size` spells: ASCII digits alone, from 1 to 100. Other scripts' digits,
  /// signs and points are not a size.
  static func size(spelled text: String) -> Int? {
    guard
      text.allSatisfy({ character in
        character.isASCII && character.isNumber
      }),
      let size = Int(text),
      sizes.contains(size)
    else {
      return nil
    }

    return size
  }

  /// How many results there are in all.
  let total: Int

  /// How many come before this page.
  let offset: Int

  /// How many a page holds at most.
  let size: Int

  /// The results of this page, by their place in the list.
  var range: Range<Int> {
    let start = min(offset, total)

    return start ..< min(start + size, total)
  }

  /// Where the following page begins; `nil` on the last page.
  var nextOffset: Int? {
    let end = range.upperBound

    return end < total ? end : nil
  }
}
