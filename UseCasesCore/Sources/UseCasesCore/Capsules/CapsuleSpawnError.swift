import Foundation

/// Why node's `spawnSync` refuses a request before starting anything: a
/// synchronous throw out of `runDemoCapsule`, never a result.
public enum CapsuleSpawnError: Error, Equatable, Sendable {
  /// `argument` is node's name for it: `file`, or `args[N]`.
  case nullByteInArgument(argument: String, value: String)
  /// The resolved working directory holds a NUL.
  case nullByteInWorkingDirectory(String)
  /// The timeout is not a whole number of milliseconds.
  case timeoutNotInteger(milliseconds: Double)

  public var code: String {
    switch self {
    case .nullByteInArgument, .nullByteInWorkingDirectory: "ERR_INVALID_ARG_VALUE"
    case .timeoutNotInteger: "ERR_OUT_OF_RANGE"
    }
  }

  /// node's own text for the refusal. A refused value is shown as node's
  /// `util.inspect` shows it, cut to 128 characters.
  public var message: String {
    switch self {
    case let .nullByteInArgument(argument, value):
      "The argument '\(argument)' must be a string without null bytes. Received "
        + Self.received(value)
    case let .nullByteInWorkingDirectory(value):
      "The property 'options.cwd' must be a string, Uint8Array, or URL without null bytes. "
        + "Received \(Self.received(value))"
    case let .timeoutNotInteger(milliseconds):
      #"The value of "timeout" is out of range. It must be an integer. Received "#
        + JavaScriptNumber.text(milliseconds)
    }
  }

  /// `ERR_INVALID_ARG_VALUE`'s inspection, cut past 128 code units.
  private static func received(_ value: String) -> String {
    let inspected = Array(inspected(value).utf16)
    guard inspected.count > 128 else {
      return CodeUnits.string(inspected)
    }
    return CodeUnits.string(inspected[0 ..< 128]) + "..."
  }

  /// `util.inspect` of a string: split after each line feed once it is longer
  /// than the break length, each line quoted and escaped on its own.
  private static func inspected(_ value: String) -> String {
    let units = Array(value.utf16)
    guard units.count > 124 else {
      return quoted(units[...])
    }
    var lines: [ArraySlice<UInt16>] = []
    var start = 0
    for (index, unit) in units.enumerated() where unit == CodeUnits.lineFeed {
      lines.append(units[start ... index])
      start = index + 1
    }
    if start < units.count {
      lines.append(units[start...])
    }
    return lines.map(quoted).joined(separator: " +\n")
  }

  /// `strEscape`: single quotes unless the text holds one, then double quotes
  /// unless it holds those too, then backticks unless it holds a backtick or
  /// `${`.
  private static func quoted(_ units: ArraySlice<UInt16>) -> String {
    let apostrophe: UInt16 = 0x27
    let text = CodeUnits.string(units)
    var quote = apostrophe
    if units.contains(apostrophe) {
      if !units.contains(CodeUnits.quotationMark) {
        quote = CodeUnits.quotationMark
      } else if !units.contains(0x60), !text.contains("${") {
        quote = 0x60
      }
    }
    var output: [UInt16] = [quote]
    for unit in units {
      output += escaped(unit, quote: quote)
    }
    output.append(quote)
    return CodeUnits.string(output)
  }

  private static func escaped(
    _ unit: UInt16,
    quote: UInt16,
  ) -> [UInt16] {
    let named: [UInt16: String] = [0x08: "\\b", 0x09: "\\t", 0x0A: "\\n", 0x0C: "\\f", 0x0D: "\\r"]
    if let name = named[unit] {
      return Array(name.utf16)
    }
    if unit < 0x20 || (0x7F ... 0x9F).contains(unit) {
      return Array(("\\x" + String(format: "%02X", unit)).utf16)
    }
    if unit == CodeUnits.reverseSolidus || (unit == 0x27 && quote == 0x27) {
      return [CodeUnits.reverseSolidus, unit]
    }
    return [unit]
  }
}
