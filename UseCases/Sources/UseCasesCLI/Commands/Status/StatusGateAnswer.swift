import UseCasesCore

/// The gate's answer in the status document (`gate`).
struct StatusGateAnswer: Encodable {
  let passed: Bool
  let strict: Bool
  let blocking: [StatusGateEntry]
  let warning: [StatusGateEntry]

  init(_ gate: Gate) {
    passed = gate.passed
    strict = gate.isStrict
    blocking = gate.blocking.map(StatusGateEntry.init)
    warning = gate.warning.map(StatusGateEntry.init)
  }
}
