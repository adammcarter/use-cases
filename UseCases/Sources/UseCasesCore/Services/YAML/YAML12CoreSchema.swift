/// The YAML 1.2 core schema: the typing every authored file is read with.
struct YAML12CoreSchema: YAMLSchemaResolving {
  func resolve(_ text: String) -> YAMLResolvedScalar {
    switch text {
    case "", "~", "null", "Null", "NULL":
      .null
    case "true", "True", "TRUE":
      .boolean(true)
    case "false", "False", "FALSE":
      .boolean(false)
    case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF":
      .number(.infinity)
    case "-.inf", "-.Inf", "-.INF":
      .number(-.infinity)
    case ".nan", ".NaN", ".NAN":
      .number(.nan)
    default:
      resolveNumber(text)
    }
  }

  private func resolveNumber(_ text: String) -> YAMLResolvedScalar {
    guard text.startsLikeANumber else {
      return .text
    }

    if text.isDecimalDigits {
      return .integer(
        YAMLInteger(
          digits: Substring(text),
          radix: 10,
          isNegative: false,
        ),
      )
    }

    if let match = text.wholeMatch(of: /(?<sign>[-+]?)(?<digits>[0-9]+)/) {
      return .integer(
        YAMLInteger(
          digits: match.digits,
          radix: 10,
          isNegative: match.sign == "-",
        ),
      )
    }

    if let match = text.wholeMatch(of: /0o(?<digits>[0-7]+)/) {
      return .integer(
        YAMLInteger(
          digits: match.digits,
          radix: 8,
          isNegative: false,
        ),
      )
    }

    if let match = text.wholeMatch(of: /0x(?<digits>[0-9a-fA-F]+)/) {
      return .integer(
        YAMLInteger(
          digits: match.digits,
          radix: 16,
          isNegative: false,
        ),
      )
    }

    if text.wholeMatch(of: /[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?/) != nil {
      // A float too big for a Double has no value to give; it reads as infinity.
      return .number(Double(text) ?? .infinity)
    }

    return .text
  }
}
