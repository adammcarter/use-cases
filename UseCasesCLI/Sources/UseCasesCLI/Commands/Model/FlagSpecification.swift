/// One flag a command declares: how it is parsed and how help shows it.
struct FlagSpecification: Sendable, Equatable {
  /// The key the parsed value is stored under, e.g. `dataRoot`.
  let key: String

  /// The spelling on the command line, dashes included.
  let name: String

  let kind: FlagKind
  let summary: String

  /// The placeholder help shows after a value-bearing flag, e.g. `<path>`.
  let valueName: String?

  /// Every occurrence is collected instead of the first.
  let isRepeatable: Bool

  /// Shown in help only; the parser does not enforce it.
  let isRequired: Bool

  /// Left out of generated help, still dispatchable.
  let isHidden: Bool

  init(
    key: String,
    name: String,
    kind: FlagKind,
    summary: String,
    valueName: String? = nil,
    isRepeatable: Bool = false,
    isRequired: Bool = false,
    isHidden: Bool = false,
  ) {
    self.key = key
    self.name = name
    self.kind = kind
    self.summary = summary
    self.valueName = valueName
    self.isRepeatable = isRepeatable
    self.isRequired = isRequired
    self.isHidden = isHidden
  }
}
