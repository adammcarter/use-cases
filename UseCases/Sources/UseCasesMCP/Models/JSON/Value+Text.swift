import MCP

extension Value {
  /// The text a command line takes for a scalar argument: a string as it is, an integer as
  /// digits, and a number with no fraction as an integer. `nil` for anything else.
  var argumentText: String? {
    switch self {
    case let .string(text):
      text
    case let .int(number):
      String(number)
    case let .double(number):
      if number.isFinite, number.rounded() == number, let whole = Int(exactly: number) {
        String(whole)
      } else {
        nil
      }
    default:
      nil
    }
  }
}
