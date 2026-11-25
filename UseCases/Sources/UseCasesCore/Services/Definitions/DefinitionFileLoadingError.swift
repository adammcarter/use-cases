/// Why a definition file did not become a ``DefinitionFile``.
enum DefinitionFileLoadingError: Error, Equatable, Sendable {
  /// Every problem found in the file, sorted. The file's use cases are not usable.
  case invalid([Diagnostic])
}
