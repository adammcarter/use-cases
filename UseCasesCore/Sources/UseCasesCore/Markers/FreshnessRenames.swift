/// JavaScript's reading of a parsed JSON value that may be absent (`undefined`).
enum JavaScriptValue {
  /// Truthiness: absent, `null`, `false`, `0`, `NaN` and `""` are falsy.
  static func isTruthy(_ value: JSONValue?) -> Bool {
    switch value {
    case .none, .null:
      false
    case let .bool(flag):
      flag
    case let .number(number):
      number != 0 && !number.isNaN
    case let .string(text):
      !text.isEmpty
    case .array, .object:
      true
    }
  }

  /// `value === text`: only a string with identical code units.
  static func strictlyEquals(
    _ value: JSONValue?,
    _ text: String?,
  ) -> Bool {
    switch (value, text) {
    case (.none, .none):
      true
    case let (.string(left), .some(right)):
      JavaScriptString.identical(left, right)
    default:
      false
    }
  }

  /// `` `${value}` ``, with `undefined` for an absent value.
  static func text(_ value: JSONValue?) -> String {
    JavaScriptString.text(of: value)
  }
}

/// Likely renames (freshness.ts `inferRenames`): an unregistered marker whose
/// row id is close to a row that lost its binding. Advisory only.
enum FreshnessRenames {
  /// A rename is only suggested well above chance similarity.
  static let similarityThreshold = 0.6

  /// Sørensen–Dice over bigrams of UTF-16 code units.
  static func similarity(
    _ left: String,
    _ right: String,
  ) -> Double {
    if JavaScriptString.identical(left, right) {
      return 1
    }
    let leftGrams = bigrams(left)
    let rightGrams = bigrams(right)
    var shared = 0
    for (gram, count) in leftGrams {
      shared += min(count, rightGrams[gram] ?? 0)
    }
    let total = leftGrams.values.reduce(0, +) + rightGrams.values.reduce(0, +)
    return total == 0 ? 0 : Double(2 * shared) / Double(total)
  }

  /// Each unregistered binding slug mapped to the row id it was most likely
  /// renamed FROM, in unregistered order. `candidates` are row ids of lost
  /// rows; a non-string one scores zero, exactly as it does in the TypeScript.
  static func infer(
    unregistered: [UnregisteredDetection],
    candidates: [JSONValue],
  ) -> OrderedStringMap<String> {
    var result = OrderedStringMap<String>()
    guard !candidates.isEmpty else {
      return result
    }
    // One lost row reaching both routes is one candidate, not a tie.
    let rowIdentifiers = OrderedStringSet(candidates.compactMap(\.stringValue)).members
    for detection in unregistered {
      let scored = rowIdentifiers
        .map { rowIdentifier in
          (rowIdentifier: rowIdentifier, score: similarity(detection.rowIdentifier, rowIdentifier))
        }
        .filter { candidate in
          candidate.score >= similarityThreshold
        }
        .enumerated()
        .sorted { left, right in
          left.element.score == right.element.score
            ? left.offset < right.offset
            : left.element.score > right.element.score
        }
        .map(\.element)
      guard let best = scored.first else {
        continue
      }
      if scored.count > 1, scored[0].score == scored[1].score {
        continue
      }
      result[detection.bindingSlug] = best.rowIdentifier
    }
    return result
  }

  /// The reverse view: previous row id to the id it was probably renamed TO.
  /// Later renames of the same previous row overwrite earlier ones.
  static func renamedTo(
    _ renamedFrom: OrderedStringMap<String>,
    unregistered: [UnregisteredDetection],
  ) -> OrderedStringMap<String> {
    var result = OrderedStringMap<String>()
    for (bindingSlug, previousRowIdentifier) in renamedFrom.pairs {
      if let detection = unregistered.first(where: { entry in
        JavaScriptString.identical(entry.bindingSlug, bindingSlug)
      }) {
        result[previousRowIdentifier] = detection.rowIdentifier
      }
    }
    return result
  }

  /// Give each global error the cure for ITS code, unless it already carries
  /// a truthy one.
  static func remediate(
    _ errors: inout [JSONObject],
    renamedTo: OrderedStringMap<String>,
  ) {
    for index in errors.indices {
      let error = errors[index]
      guard !JavaScriptValue.isTruthy(error["remediation"]) else {
        continue
      }
      if JavaScriptValue.strictlyEquals(error["code"], "REGISTRY_ROW_MISSING") {
        errors[index]["remediation"] = .string(registryRowMissingRemediation(error, renamedTo))
      } else if JavaScriptValue.strictlyEquals(error["code"], "LEDGER_INTEGRITY_ERROR") {
        errors[index]["remediation"] = .string(
          "inspect the ledger with `uc validate-ledger` — "
            + "a proof/binding ledger entry is malformed or out of order",
        )
      }
    }
  }

  private static func registryRowMissingRemediation(
    _ error: JSONObject,
    _ renamedTo: OrderedStringMap<String>,
  ) -> String {
    let rowIdentifier = error["row_id"]
    let newRowIdentifier = JavaScriptValue.isTruthy(rowIdentifier)
      ? rowIdentifier?.stringValue.flatMap { previous in
        renamedTo[previous]
      }
      : nil
    if let newRowIdentifier, !newRowIdentifier.isEmpty {
      let previous = JavaScriptValue.text(rowIdentifier)
      return "looks like \(previous) was renamed to \(newRowIdentifier). "
        + "`uc bind` fails closed while "
        + "the stale registration stands, so release it first: run "
        + "`uc unbind --row \(previous) --reason row_renamed`, then "
        + "`uc bind --row \(newRowIdentifier) --file <file> --register-existing`"
    }
    let unnamed = rowIdentifier == nil || rowIdentifier == .null
    let row = unnamed ? "a row" : JavaScriptValue.text(rowIdentifier)
    let placeholder = unnamed ? "<row>" : JavaScriptValue.text(rowIdentifier)
    return "the registry still binds \(row), which no longer exists in the "
      + "matrix. Restore the row to the matrix, or release the stale registration with "
      + "`uc unbind --row \(placeholder)` and re-register the binding against "
      + "the row that replaced it"
  }

  private static func bigrams(_ value: String) -> [[UInt16]: Int] {
    let units = Array(value.utf16)
    var counts: [[UInt16]: Int] = [:]
    var index = 0
    while index < units.count - 1 {
      counts[[units[index], units[index + 1]], default: 0] += 1
      index += 1
    }
    return counts
  }
}
