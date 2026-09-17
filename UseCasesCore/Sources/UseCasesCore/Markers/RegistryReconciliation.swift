/// One row's reconciliation sets, each sorted in code-unit order.
public struct RowReconciliation: Equatable, Sendable {
  public let rowIdentifier: String
  public let registeredBindingSlugs: [String]
  public let currentBindingSlugs: [String]
  /// Registered with no current marker: SUSPECT / BINDING_REMOVED.
  public let missingRegisteredBindingSlugs: [String]
  /// A current marker not registered for its row: INVALID.
  public let unregisteredCurrentBindingSlugs: [String]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("registered_binding_slugs", .array(registeredBindingSlugs.map(JSONValue.string))),
      ("current_binding_slugs", .array(currentBindingSlugs.map(JSONValue.string))),
      (
        "missing_registered_binding_slugs",
        .array(missingRegisteredBindingSlugs.map(JSONValue.string))
      ),
      (
        "unregistered_current_binding_slugs",
        .array(unregisteredCurrentBindingSlugs.map(JSONValue.string))
      ),
    ]))
  }
}

public struct UnregisteredDetection: Equatable, Sendable {
  public let bindingSlug: String
  public let rowIdentifier: String
  public let filePath: String
  public let startLine: Int

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("binding_slug", .string(bindingSlug)),
      ("row_id", .string(rowIdentifier)),
      ("file_path", .string(filePath)),
      ("start_line", .number(Double(startLine))),
    ]))
  }
}

public struct MissingDetection: Equatable, Sendable {
  public let bindingSlug: String
  public let rowIdentifier: String

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("binding_slug", .string(bindingSlug)),
      ("row_id", .string(rowIdentifier)),
    ]))
  }
}

public struct ReconciliationResult: Equatable, Sendable {
  public let rows: [RowReconciliation]
  public let unregistered: [UnregisteredDetection]
  public let missing: [MissingDetection]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("rows", .array(rows.map(\.jsonValue))),
      ("unregistered", .array(unregistered.map(\.jsonValue))),
      ("missing", .array(missing.map(\.jsonValue))),
    ]))
  }
}

/// The registry against a current scan (reconcile.ts, spec section 7). Derives
/// sets only; it assigns no statuses.
public enum RegistryReconciliation {
  public static func reconcile(
    registry: MaterializedRegistry,
    scan: ScanResult,
  ) -> ReconciliationResult {
    var currentByRow = OrderedStringMap<OrderedStringSet>()
    for binding in scan.bindings {
      var slugs = currentByRow[binding.rowIdentifier] ?? OrderedStringSet()
      slugs.insert(binding.bindingSlug)
      currentByRow[binding.rowIdentifier] = slugs
    }
    // A row whose markers are all gone still appears (spec 7.3).
    let rowIdentifiers = OrderedStringSet(registry.rows.keys + currentByRow.keys)

    var rows: [RowReconciliation] = []
    var missing: [MissingDetection] = []
    for rowIdentifier in rowIdentifiers.sortedMembers {
      let registered = registry.rows[rowIdentifier] ?? OrderedStringSet()
      let current = currentByRow[rowIdentifier] ?? OrderedStringSet()
      let missingSlugs = JavaScriptString.sorted(registered.members.filter { slug in
        !current.contains(slug)
      })
      let unregisteredSlugs = JavaScriptString.sorted(current.members.filter { slug in
        !registered.contains(slug)
      })
      missing += missingSlugs.map { slug in
        MissingDetection(bindingSlug: slug, rowIdentifier: rowIdentifier)
      }
      rows.append(RowReconciliation(
        rowIdentifier: rowIdentifier,
        registeredBindingSlugs: registered.sortedMembers,
        currentBindingSlugs: current.sortedMembers,
        missingRegisteredBindingSlugs: missingSlugs,
        unregisteredCurrentBindingSlugs: unregisteredSlugs,
      ))
    }

    let unregistered = scan.bindings
      .filter { binding in
        guard let row = registry.rowIdentifier(forSlug: binding.bindingSlug) else {
          return true
        }
        return !JavaScriptString.identical(row, binding.rowIdentifier)
      }
      .map { binding in
        UnregisteredDetection(
          bindingSlug: binding.bindingSlug,
          rowIdentifier: binding.rowIdentifier,
          filePath: binding.filePath,
          startLine: binding.startMarker.line,
        )
      }
    return ReconciliationResult(rows: rows, unregistered: unregistered, missing: missing)
  }
}
