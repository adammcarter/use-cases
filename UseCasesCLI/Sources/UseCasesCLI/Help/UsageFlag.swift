import Foundation
import UseCasesCore

/// One flag line in the usage catalog, e.g. `--repo <path>`.
struct UsageFlag: Sendable, Equatable {
  let flag: String
  let summary: String

  init(
    flag: String,
    summary: String,
  ) {
    self.flag = flag
    self.summary = summary
  }

  /// A boolean flag is bare; a value-bearing one carries its placeholder.
  init(_ specification: FlagSpecification) {
    let flag = specification.kind == .boolean
      ? specification.name
      : "\(specification.name) \(specification.valueName ?? "")"
    self.init(
      flag: flag.trimmingCharacters(in: .whitespacesAndNewlines),
      summary: specification.summary,
    )
  }

  var jsonValue: JSONValue {
    .object(JSONObject([("flag", .string(flag)), ("summary", .string(summary))]))
  }
}
