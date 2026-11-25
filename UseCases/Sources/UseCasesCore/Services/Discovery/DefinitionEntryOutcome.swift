/// What one entry below a `use_cases_dir` means for definition discovery.
enum DefinitionEntryOutcome {
  /// A folder to search.
  case descend(WorkspacePath)

  /// A `.yml` or `.yaml` file that is a definition.
  case definition(WorkspacePath)

  /// Something INVALID in a `use_cases_dir`.
  case refuse(Diagnostic)

  /// Nothing to do with definitions.
  case skip
}
