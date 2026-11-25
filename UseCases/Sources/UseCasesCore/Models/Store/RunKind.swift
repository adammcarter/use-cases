/// What produced a run's verdicts (chapter 12 §5). Its raw value is the text the manifest keeps.
enum RunKind: String, CaseIterable, Sendable {
  /// `use-cases verify`: the reports the run's tests wrote.
  case verify

  /// `use-cases record`: a verdict a person or agent supplied.
  case record
}
