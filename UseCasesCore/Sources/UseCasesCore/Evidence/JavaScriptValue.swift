/// How the evidence TypeScript reads a parsed JSON value, where Swift's nil
/// stands for `undefined` — added to the truthiness and `===` the freshness
/// port already has.
///
/// Past the four-field event shape check nothing in a ledger is validated, so
/// replay reads members off whatever JSON a line holds: a member of a
/// non-object is `undefined`, and `??` falls through `null` as well as
/// `undefined`.
extension JavaScriptValue {
  /// `value.key` for a value already known not to be null or undefined: a
  /// string, number, boolean or array has none of the members replay reads.
  static func member(
    _ value: JSONValue?,
    _ key: String,
  ) -> JSONValue? {
    value?.objectValue?[key]
  }

  /// True for `undefined` and `null`, the values `??` replaces.
  static func isNullish(_ value: JSONValue?) -> Bool {
    value == nil || value == .null
  }

  /// `value ?? fallback`.
  static func coalesce(
    _ value: JSONValue?,
    _ fallback: JSONValue?,
  ) -> JSONValue? {
    isNullish(value) ? fallback : value
  }
}

/// `JSON.parse` builds objects whose property order is ECMAScript's: array-index
/// keys first in ascending numeric order, then every other key in the order it
/// arrived. `JSON.stringify` writes them back in that order, so a parsed event
/// is reordered once, as it is read.
public enum JavaScriptPropertyOrder {
  public static func reordered(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .array(items):
      return .array(items.map(reordered))
    case let .object(object):
      var indexed: [(index: UInt64, member: (String, JSONValue))] = []
      var named: [(String, JSONValue)] = []
      for member in object.pairs {
        if let index = arrayIndex(member.key) {
          indexed.append((index, (member.key, reordered(member.value))))
        } else {
          named.append((member.key, reordered(member.value)))
        }
      }
      let ordered = indexed.sorted { left, right in
        left.index < right.index
      }
      return .object(JSONObject(ordered.map(\.member) + named))
    default:
      return value
    }
  }

  /// The key as an ECMAScript array index — a canonical decimal integer below
  /// 2^32 - 1 — or nil.
  private static func arrayIndex(_ key: String) -> UInt64? {
    let units = Array(key.utf16)
    guard !units.isEmpty, units.count <= 10, units.allSatisfy(CodeUnits.isASCIIDigit),
          units.count == 1 || units[0] != 0x30,
          let number = UInt64(key), number < 4_294_967_295
    else {
      return nil
    }
    return number
  }
}

/// `hasDuplicateJsonKeys` in jsonlLedger.ts: a textual scan, not a parse.
///
/// A key's token is its characters with every backslash and the character
/// after it dropped, so `"a\"b"` and `"a\\b"` are both `ab` and count as
/// duplicates; a string counts as a key when the next non-whitespace after its
/// closing quote is `:` and some object is open. Ported over UTF-16 code units
/// because that is what the TypeScript indexes.
enum DuplicateJSONKeys {
  static func isPresent(in units: [UInt16]) -> Bool {
    var scan = Scan(units: units)
    for index in units.indices where scan.step(at: index) {
      return true
    }
    return false
  }

  private struct Scan {
    let units: [UInt16]
    var stack: [Set<[UInt16]>] = []
    var isInString = false
    var isEscaped = false
    var token: [UInt16] = []

    /// Reads one code unit; true once a key repeats in its object.
    mutating func step(at index: Int) -> Bool {
      let unit = units[index]
      guard isInString else {
        outside(unit)
        return false
      }
      if isEscaped {
        isEscaped = false
      } else if unit == CodeUnits.reverseSolidus {
        isEscaped = true
      } else if unit == CodeUnits.quotationMark {
        isInString = false
        defer {
          token = []
        }
        return closesRepeatedKey(at: index)
      } else {
        token.append(unit)
      }
      return false
    }

    private mutating func outside(_ unit: UInt16) {
      switch unit {
      case CodeUnits.quotationMark:
        isInString = true
        token = []
      case CodeUnits.leftCurlyBracket:
        stack.append([])
      case CodeUnits.rightCurlyBracket:
        _ = stack.popLast()
      default:
        break
      }
    }

    /// The string just closed is a key — the next non-whitespace is `:`
    /// (`source.slice(index + 1).trimStart().startsWith(":")`) and an object is
    /// open — that its object already holds.
    private mutating func closesRepeatedKey(at index: Int) -> Bool {
      var position = index + 1
      while position < units.count, CodeUnits.isJavaScriptWhitespace(units[position]) {
        position += 1
      }
      guard position < units.count, units[position] == CodeUnits.colon, !stack.isEmpty else {
        return false
      }
      return !stack[stack.count - 1].insert(token).inserted
    }
  }
}
