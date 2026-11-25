/// What the folders of a workspace hold under the name of a file Use Cases owns, such as
/// `use-case-groups.yml` (chapter 09 §19, §21).
struct OwnedFileLocation: Equatable, Sendable {
  /// What the root holds under exactly this name; `nil` when it holds nothing so named.
  let entry: FileEntry?

  /// What is wrong with the other places the name is found: a lookalike spelled in another case
  /// or Unicode form, in any folder of a scope, and the file itself in a child scope.
  let diagnostics: [Diagnostic]
}
