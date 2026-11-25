/// Why a transformer's job gave no answer the core can use (chapter 10 §14). Each case carries
/// the name the bridge settings give the transformer, so a message names it (chapter 09 §20.4).
enum TransformerError: Error, Equatable, Sendable {
  /// A bundled transformer's program is not beside the running `use-cases`.
  case programMissing(
    name: String,
    expectedAt: String,
  )

  /// The program could not be started: not there, not executable, no interpreter.
  case couldNotLaunch(
    name: String,
    reason: String,
  )

  /// The private folder for the request and the response could not be made or written.
  case scratchUnavailable(
    name: String,
    reason: String,
  )

  /// The transformer was still running when its time ran out, and was stopped.
  case timedOut(
    name: String,
    after: Duration,
  )

  /// A signal killed the transformer.
  case signaled(
    name: String,
    signal: Int32,
  )

  /// The transformer exited with a code other than 0; `console` is the end of what it printed.
  case exited(
    name: String,
    code: Int32,
    console: String,
  )

  /// The response is missing, is not JSON, is not an object, or has a member of the wrong type.
  case malformedResponse(
    name: String,
    reason: String,
  )

  /// The response does not say `"contract": 1`.
  case unsupportedContract(name: String)

  /// A links transformer returned a link the core cannot place (chapter 10 §11); `link` is the
  /// link as it came.
  case badLink(
    name: String,
    link: String,
    problem: TransformerLinkProblem,
  )

  /// A results transformer reported a result for a link that is not a validation link of the
  /// request (chapter 10 §14).
  case unknownResultLink(
    name: String,
    link: String,
  )

  /// A results transformer reported a status other than `pass`, `fail`, `error` and `incomplete`
  /// (chapter 10 §14).
  case invalidResultStatus(
    name: String,
    link: String,
    status: String,
  )

  /// The run was cancelled while the transformer ran, and the transformer was stopped.
  case cancelled
}
