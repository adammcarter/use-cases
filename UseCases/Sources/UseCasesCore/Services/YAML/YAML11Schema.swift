/// The YAML 1.1 typing (yaml.org/type), kept only to find the plain scalars it would type
/// differently from the core schema. The float patterns require a digit, as real readers do.
/// The single letters `y` and `n` are not read as booleans: chapter 09 §14 lists only `on`, `off`,
/// `yes` and `no`, and the acceptance suite's fixtures write a plain `y`.
struct YAML11Schema: YAMLSchemaResolving {
  func resolve(_ text: String) -> YAMLResolvedScalar {
    if let word = resolveWord(text) {
      return word
    }

    guard text.startsLikeANumber else {
      return .text
    }

    if let integer = resolveInteger(text) {
      return integer
    }

    if let number = resolveNumber(text) {
      return number
    }

    if isTimestamp(text) {
      return .timestamp
    }

    return .text
  }

  private func resolveWord(_ text: String) -> YAMLResolvedScalar? {
    switch text {
    case "", "~", "null", "Null", "NULL":
      return .null
    case "true", "True", "TRUE":
      return .boolean(true)
    case "false", "False", "FALSE":
      return .boolean(false)
    case "<<":
      return .mergeKey
    case "=":
      return .valueKey
    default:
      break
    }

    switch text.lowercased() {
    case "yes", "on":
      return .boolean(true)
    case "no", "off":
      return .boolean(false)
    default:
      return nil
    }
  }

  private func resolveInteger(_ text: String) -> YAMLResolvedScalar? {
    if text.isDecimalDigits, text == "0" || !text.hasPrefix("0") {
      return integer(
        Substring(text),
        radix: 10,
        sign: "",
      )
    }

    if let match = text.wholeMatch(of: /(?<sign>[-+]?)0b(?<digits>[01_]+)/) {
      return integer(match.digits, radix: 2, sign: match.sign)
    }

    if let match = text.wholeMatch(of: /(?<sign>[-+]?)0x(?<digits>[0-9a-fA-F_]+)/) {
      return integer(match.digits, radix: 16, sign: match.sign)
    }

    if let match = text.wholeMatch(of: /(?<sign>[-+]?)0(?<digits>[0-7_]+)/) {
      return integer(match.digits, radix: 8, sign: match.sign)
    }

    if let match = text.wholeMatch(of: /(?<sign>[-+]?)(?<digits>0|[1-9][0-9_]*)/) {
      return integer(match.digits, radix: 10, sign: match.sign)
    }

    if text.wholeMatch(of: /[-+]?[1-9][0-9_]*(:[0-5]?[0-9])+/) != nil {
      return .sexagesimal
    }

    return nil
  }

  private func resolveNumber(_ text: String) -> YAMLResolvedScalar? {
    if text.wholeMatch(of: /[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+\.[0-9_]*/) != nil {
      return .sexagesimal
    }

    if text.wholeMatch(of: /[-+]?[0-9][0-9_]*\.[0-9_]*([eE][-+][0-9]+)?/) != nil
      || text.wholeMatch(of: /[-+]?\.[0-9_]+([eE][-+][0-9]+)?/) != nil
    {
      guard let value = Double(text.filter { $0 != "_" }) else {
        return nil
      }

      return .number(value)
    }

    if text.wholeMatch(of: /\+?\.(inf|Inf|INF)/) != nil {
      return .number(.infinity)
    }

    if text.wholeMatch(of: /-\.(inf|Inf|INF)/) != nil {
      return .number(-.infinity)
    }

    if text.wholeMatch(of: /\.(nan|NaN|NAN)/) != nil {
      return .number(.nan)
    }

    return nil
  }

  private func isTimestamp(_ text: String) -> Bool {
    let dateAndTime = #/
      [0-9]{4}-[0-9]{1,2}-[0-9]{1,2}
      ([Tt]|[\x20\t]+)
      [0-9]{1,2}:[0-9]{2}:[0-9]{2}
      (\.[0-9]*)?
      ([\x20\t]*(Z|[-+][0-9]{1,2}(:[0-9]{2})?))?
    /#

    return text.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil
      || text.wholeMatch(of: dateAndTime) != nil
  }

  private func integer(
    _ digits: Substring,
    radix: Int,
    sign: Substring,
  ) -> YAMLResolvedScalar {
    .integer(
      YAMLInteger(
        digits: digits,
        radix: radix,
        isNegative: sign == "-",
      ),
    )
  }
}
