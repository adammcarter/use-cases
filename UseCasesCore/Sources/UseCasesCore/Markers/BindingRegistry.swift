/// A registry event's type.
public enum RegistryEventType: String, Equatable, Sendable {
  case bindingRegistered = "binding_registered"
  case bindingReleased = "binding_released"
}

/// Every way the registry can be invalid (spec 4.3 / 7.1). Frozen wire codes.
public enum RegistryErrorCode: String, CaseIterable, Equatable, Sendable {
  case jsonParseError = "JSON_PARSE_ERROR"
  case registrySchemaInvalid = "REGISTRY_SCHEMA_INVALID"
  case slugPrefixMismatch = "SLUG_PREFIX_MISMATCH"
  case registryRowMissing = "REGISTRY_ROW_MISSING"
  case duplicateRegistration = "DUPLICATE_REGISTRATION"
  case slugRowConflict = "SLUG_ROW_CONFLICT"
  case releaseWithoutRegistration = "RELEASE_WITHOUT_REGISTRATION"
}

public struct RegistryError: Equatable, Sendable {
  public let code: RegistryErrorCode
  /// 1-based source line, or nil when not line-bound.
  public let line: Int?
  public let message: String
  public let bindingSlug: String?
  public let rowIdentifier: String?

  init(
    code: RegistryErrorCode,
    line: Int?,
    message: String,
    bindingSlug: String? = nil,
    rowIdentifier: String? = nil,
  ) {
    self.code = code
    self.line = line
    self.message = message
    self.bindingSlug = bindingSlug
    self.rowIdentifier = rowIdentifier
  }

  /// `{ code, line, message, binding_slug?, row_id? }`.
  public var jsonValue: JSONValue {
    var object = JSONObject([
      ("code", .string(code.rawValue)),
      ("line", JSONValue.optionalNumber(line)),
      ("message", .string(message)),
    ])
    object["binding_slug"] = bindingSlug.map(JSONValue.string)
    object["row_id"] = rowIdentifier.map(JSONValue.string)
    return .object(object)
  }
}

/// One schema-valid registry event, with the parsed value kept as written.
public struct RegistryEvent: Equatable, Sendable {
  public let eventType: RegistryEventType
  public let rowIdentifier: String
  public let bindingSlug: String
  public let json: JSONValue
}

/// One parsed JSONL line; `value` is parsed but not yet validated.
public struct RegistryLine: Equatable, Sendable {
  public let line: Int
  public let value: JSONValue
}

public struct ReadRegistryResult: Equatable, Sendable {
  public let lines: [RegistryLine]
  /// JSON_PARSE_ERROR entries only.
  public let errors: [RegistryError]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("lines", .array(lines.map { entry in
        .object(JSONObject([("line", .number(Double(entry.line))), ("value", entry.value)]))
      })),
      ("errors", .array(errors.map(\.jsonValue))),
    ]))
  }
}

public struct RowBindingSlugs: Equatable, Sendable {
  public let rowIdentifier: String
  public let bindingSlugs: [String]
}

public struct SlugRow: Equatable, Sendable {
  public let bindingSlug: String
  public let rowIdentifier: String
}

/// The registry folded from its events, in the insertion order the TypeScript's
/// `Map`s and `Set`s keep.
public struct MaterializedRegistry: Sendable {
  var rows = OrderedStringMap<OrderedStringSet>()
  var slugs = OrderedStringMap<String>()

  public var rowToSlugs: [RowBindingSlugs] {
    rows.pairs.map { pair in
      RowBindingSlugs(rowIdentifier: pair.key, bindingSlugs: pair.value.members)
    }
  }

  public var slugToRow: [SlugRow] {
    slugs.pairs.map { pair in
      SlugRow(bindingSlug: pair.key, rowIdentifier: pair.value)
    }
  }

  public func bindingSlugs(forRow rowIdentifier: String) -> [String]? {
    rows[rowIdentifier]?.members
  }

  public func rowIdentifier(forSlug bindingSlug: String) -> String? {
    slugs[bindingSlug]
  }

  mutating func register(
    _ slug: String,
    to row: String,
  ) {
    slugs[slug] = row
    var members = rows[row] ?? OrderedStringSet()
    members.insert(slug)
    rows[row] = members
  }

  /// End a slug's registration; a row left with no slugs disappears.
  mutating func release(_ slug: String) {
    guard let row = slugs[slug] else {
      return
    }
    slugs[slug] = nil
    guard var members = rows[row] else {
      return
    }
    members.remove(slug)
    rows[row] = members.isEmpty ? nil : members
  }
}

public struct RegistryValidationResult: Sendable {
  public let isValid: Bool
  public let errors: [RegistryError]
  /// Events that passed every rule, in order.
  public let events: [RegistryEvent]
  public let registry: MaterializedRegistry
}

/// The append-only binding registry (registry.ts, spec section 4): pure text
/// in, validated events and a materialized registry out.
public enum BindingRegistry {
  /// One parsed value per non-blank line; a line that is not JSON is a
  /// JSON_PARSE_ERROR carrying its 1-based number, and reading continues.
  public static func read(_ text: String) -> ReadRegistryResult {
    var lines: [RegistryLine] = []
    var errors: [RegistryError] = []
    for (index, raw) in JavaScriptString.split(text, on: CodeUnits.lineFeed).enumerated() {
      guard !JavaScriptString.trim(raw).isEmpty else {
        continue
      }
      let number = index + 1
      do throws(SchemaError) {
        try lines.append(RegistryLine(line: number, value: JSONParser.parse(raw)))
      } catch {
        errors.append(RegistryError(
          code: .jsonParseError,
          line: number,
          message: "line \(number) is not valid JSON: \(error.message)",
        ))
      }
    }
    return ReadRegistryResult(lines: lines, errors: errors)
  }

  public static func validate(
    text: String,
    yamlRowIdentifiers: Set<String>,
  ) -> RegistryValidationResult {
    validate(read(text), yamlRowIdentifiers: yamlRowIdentifiers)
  }

  //: @use-case:lifecycle.bindings.retired_row_can_leave_the_matrix
  /// Validate in order against the schema and the spec 4.3 rules, folding the
  /// accepted events. Rule 5 (the row exists) runs over the LIVE slugs after
  /// the fold, so a row may leave the matrix once its bindings are released.
  public static func validate(
    _ read: ReadRegistryResult,
    yamlRowIdentifiers: Set<String>,
  ) -> RegistryValidationResult {
    var fold = RegistryFold()
    fold.errors = read.errors
    for entry in read.lines {
      fold.apply(entry)
    }
    let knownRows = Set(yamlRowIdentifiers.map(CodeUnitKey.init))
    for (slug, line) in fold.registeredAtLine.pairs {
      guard let row = fold.registry.rowIdentifier(forSlug: slug),
            !knownRows.contains(CodeUnitKey(row))
      else {
        continue
      }
      fold.errors.append(RegistryError(
        code: .registryRowMissing,
        line: line,
        message: "row_id \(row) is not a known YAML row",
        bindingSlug: slug,
        rowIdentifier: row,
      ))
    }
    return RegistryValidationResult(
      isValid: fold.errors.isEmpty,
      errors: fold.errors,
      events: fold.events,
      registry: fold.registry,
    )
  }

  //: @use-case:end lifecycle.bindings.retired_row_can_leave_the_matrix

  /// Fold already-validated events; no conflict checks are repeated.
  public static func materialize(_ events: [RegistryEvent]) -> MaterializedRegistry {
    var registry = MaterializedRegistry()
    for event in events {
      switch event.eventType {
      case .bindingReleased:
        registry.release(event.bindingSlug)
      case .bindingRegistered:
        registry.register(event.bindingSlug, to: event.rowIdentifier)
      }
    }
    return registry
  }
}
