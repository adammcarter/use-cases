/// What running one command step produced (`DemoCapsuleCommandResult`).
public struct DemoCapsuleCommandResult: Sendable, Equatable {
  public let itemIndex: Int
  public let stepIndex: Int
  public let useCaseIdentifier: String
  public let step: DemoCapsuleCommandStep
  /// Nil when the program never started or a signal ended it.
  public let exitCode: Int?
  /// The signal's name, e.g. `SIGTERM`, when one ended the program.
  public let signal: String?
  /// Redacted, then cut to 16,384 UTF-16 code units.
  public let standardOutput: String
  /// Redacted, then cut to 16,384 UTF-16 code units; node's spawn error when
  /// the program never started.
  public let standardError: String

  public init(
    itemIndex: Int,
    stepIndex: Int,
    useCaseIdentifier: String,
    step: DemoCapsuleCommandStep,
    exitCode: Int?,
    signal: String?,
    standardOutput: String,
    standardError: String,
  ) {
    self.itemIndex = itemIndex
    self.stepIndex = stepIndex
    self.useCaseIdentifier = useCaseIdentifier
    self.step = step
    self.exitCode = exitCode
    self.signal = signal
    self.standardOutput = standardOutput
    self.standardError = standardError
  }

  /// The exit code is one of the step's expected codes.
  public var isExpectedExitCode: Bool {
    guard let exitCode else {
      return false
    }
    return step.expectedExitCodes.contains(Double(exitCode))
  }

  /// The TypeScript's result object, members in its order.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("item_index", .number(Double(itemIndex))),
      ("step_index", .number(Double(stepIndex))),
      ("use_case_id", .string(useCaseIdentifier)),
      ("executable", .string(step.executable)),
      ("argv", .array(step.arguments.map(JSONValue.string))),
      ("working_directory", .string(step.workingDirectory)),
      ("exit_code", exitCode.map { code in
        .number(Double(code))
      } ?? .null),
      ("signal", signal.map(JSONValue.string) ?? .null),
      ("stdout", .string(standardOutput)),
      ("stderr", .string(standardError)),
      ("expected_exit_codes", .array(step.expectedExitCodes.map(JSONValue.number))),
      ("matched_expected_exit_code", .bool(isExpectedExitCode)),
    ]))
  }
}
