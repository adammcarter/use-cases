/// The three streams a started command gets, as open descriptors of this process.
struct ProcessStreams {
  /// Read as the command's stdin, from its start; `nil` is `/dev/null`.
  let input: Int32?

  /// Written as the command's stdout.
  let output: Int32

  /// Written as the command's stderr; the same descriptor as `output` keeps the two in the order
  /// the command wrote them.
  let error: Int32

  /// A descriptor of this process handed to the command as its lifeline (``ProcessLifeline``);
  /// `nil` hands it none.
  var lifeline: Int32?
}
