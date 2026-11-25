/// Who holds SIGINT and SIGTERM for the process, and whether one has come.
protocol SignalOwning: Actor {
  /// Whether a signal has been seen since the signals were taken over, or the program that
  /// started this one has died.
  var isCancelled: Bool { get }

  /// One more holder. The first one takes the signals over.
  func take()

  /// One holder fewer. The last one gives the signals back.
  func release()
}
