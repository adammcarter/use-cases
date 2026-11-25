/// One use-case definition file (chapter 02 and 04): an optional prefix, and its use cases in
/// the order written (chapter 09 §16).
struct DefinitionFile: Equatable, Sendable {
  /// The file's own prefix, composed after the scope prefixes.
  let prefix: Namespace?
  let useCases: [UseCaseDefinition]
}
