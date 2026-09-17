/// One verifier invocation, handed to the spawn runner (`VerifySpawnRequest`).
public struct VerifySpawnRequest: Equatable, Sendable {
  public let command: [String]
  public let workingDirectory: String
  public let timeoutSeconds: Double?

  public init(
    command: [String],
    workingDirectory: String,
    timeoutSeconds: Double?,
  ) {
    self.command = command
    self.workingDirectory = workingDirectory
    self.timeoutSeconds = timeoutSeconds
  }

  /// `{ command, cwd, timeout_seconds }`, the timeout absent when unset.
  var jsonValue: JSONValue {
    var object = JSONObject([
      ("command", .array(command.map(JSONValue.string))),
      ("cwd", .string(workingDirectory)),
    ])
    object["timeout_seconds"] = timeoutSeconds.map(JSONValue.number)
    return .object(object)
  }
}

/// The runner's verdict for one verifier invocation (`VerifySpawnResult`).
public struct VerifySpawnResult: Equatable, Sendable {
  public let exitCode: Int
  public let timedOut: Bool
  public let standardOutput: String
  public let standardError: String

  public init(
    exitCode: Int,
    timedOut: Bool,
    standardOutput: String,
    standardError: String,
  ) {
    self.exitCode = exitCode
    self.timedOut = timedOut
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

/// Why node's `spawnSync` refuses a request before starting anything. Each is
/// a synchronous throw out of `verify` in the TypeScript, never a result.
public enum VerifySpawnError: Error, Equatable, Sendable {
  /// The resolved command has no first element (`command.generic` with no
  /// argv expands to one).
  case commandMissing
  case commandEmpty
  /// `argument` is node's name for it: `file`, or `args[N]`.
  case nullByte(argument: String, value: String)
  /// The timeout in milliseconds is not a whole number.
  case timeoutNotInteger(milliseconds: Double)
  /// The timeout in milliseconds is negative or above 2^53 - 1.
  case timeoutOutOfRange(milliseconds: Double)

  public var code: String {
    switch self {
    case .commandMissing: "spawn_command_missing"
    case .commandEmpty: "spawn_command_empty"
    case .nullByte: "spawn_argument_null_byte"
    case .timeoutNotInteger: "spawn_timeout_not_integer"
    case .timeoutOutOfRange: "spawn_timeout_out_of_range"
    }
  }

  /// node's own text for the refusal.
  public var message: String {
    switch self {
    case .commandMissing:
      #"The "file" argument must be of type string. Received undefined"#
    case .commandEmpty:
      "The argument 'file' cannot be empty. Received ''"
    case let .nullByte(argument, value):
      "The argument '\(argument)' must be a string without null bytes. Received "
        + "'\(value.replacingOccurrences(of: "\u{0}", with: "\\x00"))'"
    case let .timeoutNotInteger(milliseconds):
      #"The value of "timeout" is out of range. It must be an integer. Received "#
        + JavaScriptNumber.text(milliseconds)
    case let .timeoutOutOfRange(milliseconds):
      #"The value of "timeout" is out of range. It must be >= 0 && <= 9007199254740991. "#
        + "Received \(Self.separated(milliseconds))"
    }
  }

  /// node's `addNumericalSeparator`, which it applies to an integer whose
  /// magnitude exceeds 2^32.
  private static func separated(_ value: Double) -> String {
    let text = JavaScriptNumber.text(value)
    guard abs(value) > 4_294_967_296 else {
      return text
    }
    let units = Array(text.utf16)
    let start = units.first == CodeUnits.hyphenMinus ? 1 : 0
    var end = units.count
    var suffix = ""
    while end >= start + 4 {
      suffix = "_" + CodeUnits.string(units[(end - 3) ..< end]) + suffix
      end -= 3
    }
    return CodeUnits.string(units[0 ..< end]) + suffix
  }
}

/// Runs a verifier: the process externality behind `verify`. Injected so a
/// test scripts the outcome and never runs this repository's own verifiers.
public protocol VerifySpawnRunning {
  func run(_ request: VerifySpawnRequest) throws(VerifySpawnError) -> VerifySpawnResult
}
