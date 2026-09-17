import UseCasesCore

/// One command in the usage catalog.
struct UsageEntry: Sendable, Equatable {
  let name: String
  let summary: String
  let flags: [UsageFlag]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("name", .string(name)),
      ("summary", .string(summary)),
      ("flags", .array(flags.map(\.jsonValue))),
    ]))
  }
}
