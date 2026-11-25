/// One occurrence of the bytes `@use-case:` with the id that follows it (chapter 08).
struct MarkerSentinel: Hashable, Sendable {
  let kind: MarkerSentinelKind

  /// The id as the grammar reads it: the longest run of `a-z 0-9 . # -` after the sentinel, less
  /// any trailing `-` or `.`. It may be empty or malformed; nothing has judged it yet.
  let identifier: String

  /// The bytes of the whole token: from the `@` through the last byte of the id, `end` and the
  /// spaces or tabs after it included. A trailing `-` or `.` is not part of the id, so it is not
  /// part of the token either, unless a word follows the id run: then the whole word is part of
  /// the token, and so is whatever lies between the id and the word.
  let tokenRange: Range<Int>

  /// The line the token begins on, counted from 1.
  let line: Int

  /// The ASCII letters, digits and underscores that follow the id run directly, the first 40 of
  /// them to name in a warning; empty when none does. An id run that is followed by such a word
  /// is not an id at all (`a.b#submiT` is not `a.b#submi`), and the whole word is part of the
  /// sentinel token.
  var followingWord: String = ""
}
