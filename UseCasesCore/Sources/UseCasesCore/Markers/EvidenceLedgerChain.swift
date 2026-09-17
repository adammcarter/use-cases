/// The tamper-evident chain's diagnostic codes. Frozen wire contract.
public enum LedgerChainErrorCode: String, CaseIterable, Equatable, Sendable {
  case chainBroken = "UCM_LEDGER_CHAIN_BROKEN"
  case indexGap = "UCM_LEDGER_INDEX_GAP"
  case duplicateIndex = "UCM_LEDGER_DUPLICATE_INDEX"
}

public struct LedgerChainError: Equatable, Sendable {
  public let code: LedgerChainErrorCode
  public let line: Int?
  public let message: String
  /// A JavaScript number: the entry's claimed index, as written.
  public let entryIndex: Double?

  /// `{ code, line, entry_index?, message }`.
  var jsonValue: JSONValue {
    var object = JSONObject([
      ("code", .string(code.rawValue)),
      ("line", JSONValue.optionalNumber(line)),
    ])
    object["entry_index"] = entryIndex.map(JSONValue.number)
    object["message"] = .string(message)
    return .object(object)
  }
}

public struct LedgerChainResult: Equatable, Sendable {
  /// True when the chained suffix is consistent, or there is no chain at all.
  public let isValid: Bool
  /// Chained entries that verified with no chain error.
  public let verifiedEntries: Int
  /// Leading legacy entries with no chain fields.
  public let legacyPrefixCount: Int
  public let errors: [LedgerChainError]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("ok", .bool(isValid)),
      ("verified_entries", .number(Double(verifiedEntries))),
      ("legacy_prefix_count", .number(Double(legacyPrefixCount))),
      ("errors", .array(errors.map(\.jsonValue))),
    ]))
  }
}

/// The optional tamper-evident hash chain over a ledger (evidenceLedger.ts):
/// each chained entry records its absolute index and the entry hash of the
/// entry before it. Legacy entries minted before the chain existed are a
/// tolerated prefix.
public enum EvidenceLedgerChain {
  /// `previous_entry_hash` of the first ledger entry.
  public static let genesisEntryHash = "sha256:" + String(repeating: "0", count: 64)

  /// sha256 over the FULL entry's code-unit canonical JSON, signature and
  /// chain fields included, so editing any prior entry breaks the next link.
  public static func entryHash(_ entry: JSONValue) throws(CodeUnitCanonicalJSONError) -> String {
    try CodeUnitCanonicalJSON.sha256(entry)
  }

  /// Verify the contiguous chained suffix. Signatures and schema are not this
  /// check's concern.
  public static func verify(_ lines: [EvidenceLine]) throws(CodeUnitCanonicalJSONError)
    -> LedgerChainResult
  {
    let legacyPrefixCount = lines.prefix { entry in
      !carriesChainFields(entry.value)
    }
    .count
    var errors: [LedgerChainError] = []
    var verifiedEntries = 0
    var seenIndices = Set<Double>()
    for position in lines.indices.dropFirst(legacyPrefixCount) {
      let entryErrors = try check(lines, at: position, seenIndices: &seenIndices)
      if entryErrors.isEmpty {
        verifiedEntries += 1
      } else {
        errors += entryErrors
      }
    }
    return LedgerChainResult(
      isValid: errors.isEmpty,
      verifiedEntries: verifiedEntries,
      legacyPrefixCount: legacyPrefixCount,
      errors: errors,
    )
  }

  /// The preceding entry is hashed only once both chain fields are present,
  /// exactly when the TypeScript hashes it.
  private static func check(
    _ lines: [EvidenceLine],
    at position: Int,
    seenIndices: inout Set<Double>,
  ) throws(CodeUnitCanonicalJSONError) -> [LedgerChainError] {
    let entry = lines[position]
    let line = entry.line
    guard let index = entry.value["entry_index"]?.numberValue,
          index.isFinite, index.rounded() == index,
          let previous = entry.value["previous_entry_hash"]?.stringValue
    else {
      return [LedgerChainError(
        code: .chainBroken,
        line: line,
        message: "chained ledger entry at position \(position) is missing a chain field "
          + "(entry_index/previous_entry_hash)",
        entryIndex: nil,
      )]
    }
    var errors: [LedgerChainError] = []
    let spelled = JavaScriptNumber.text(index)
    if seenIndices.contains(index) {
      errors.append(LedgerChainError(
        code: .duplicateIndex,
        line: line,
        message: "duplicate entry_index \(spelled) at ledger position \(position)",
        entryIndex: index,
      ))
    } else if index != Double(position) {
      errors.append(LedgerChainError(
        code: .indexGap,
        line: line,
        message: "entry_index \(spelled) does not match its ledger position \(position) "
          + "(gap, reorder, or truncation)",
        entryIndex: index,
      ))
    }
    seenIndices.insert(index)
    let expectedPrevious = position == 0 ? genesisEntryHash :
      try entryHash(lines[position - 1].value)
    if !JavaScriptString.identical(previous, expectedPrevious) {
      errors.append(LedgerChainError(
        code: .chainBroken,
        line: line,
        message: "previous_entry_hash does not match the preceding entry "
          + "(chain broken at position \(position))",
        entryIndex: index,
      ))
    }
    return errors
  }

  /// An entry carries the chain when EITHER field is present, even as null.
  private static func carriesChainFields(_ value: JSONValue) -> Bool {
    guard let object = value.objectValue else {
      return false
    }
    return object.contains("entry_index") || object.contains("previous_entry_hash")
  }
}
