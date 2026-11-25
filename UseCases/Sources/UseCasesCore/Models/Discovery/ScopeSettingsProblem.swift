/// One thing wrong with a scope's `use-cases.yml`, as its reader found it.
struct ScopeSettingsProblem: Equatable, Sendable {
  let position: SourcePosition?
  let code: DiagnosticCode
  let message: String
}
