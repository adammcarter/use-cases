/// What one run of git came to: how it ended and what it printed.
struct GitAnswer: Equatable {
  let exitCode: Int32

  /// Standard output and standard error together, in the order git wrote them.
  let text: String

  /// The last line git printed, which is the answer even when a warning came first.
  var lastLine: String? {
    text.split(whereSeparator: \.isNewline).last.map(String.init)
  }
}
