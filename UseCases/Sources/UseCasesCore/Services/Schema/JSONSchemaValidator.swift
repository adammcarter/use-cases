/// Checks JSON documents against a schema written in the keywords the core's checker knows
/// (Draft 2020-12, `docs/architecture.md` §6), the same checker that reads the
/// authored files. An object member the schema does not list breaks it when the schema says
/// `additionalProperties: false`.
public struct JSONSchemaValidator: JSONSchemaValidating {
  private let checker: any SchemaChecking
  private let reader: any JSONReading

  /// - Parameter schemaText: The schema, as JSON text. Refused if it uses a keyword the checker
  ///   does not support, never skipped.
  public init(schemaText: String) throws(JSONSchemaValidatorError) {
    let reader = JSONReader()
    let schema: AuthoredValue

    do {
      schema = try reader.read(schemaText)
    } catch {
      throw .notJSON(reason: error.description)
    }

    do {
      checker = try SchemaChecker(schema: schema)
    } catch {
      throw .notASchema(reason: "\(error)")
    }

    self.reader = reader
  }

  public func problems(in documentText: String) -> [JSONSchemaProblem] {
    let document: AuthoredValue

    do {
      document = try reader.read(documentText)
    } catch {
      return [.unreadable(reason: error.description)]
    }

    return checker.check(document).map { failure in
      Self.problem(of: failure)
    }
  }

  private static func problem(of failure: SchemaFailure) -> JSONSchemaProblem {
    switch failure.keyword {
    case .required where failure.members.count == 1:
      .missing(
        path: failure.pathText,
        member: failure.members[0],
      )
    case .additionalProperties where !failure.members.isEmpty:
      .unexpected(
        path: failure.pathText,
        members: failure.members,
      )
    default:
      .breaks(
        path: failure.pathText,
        keyword: failure.keyword.rawValue,
        message: failure.message,
      )
    }
  }
}
