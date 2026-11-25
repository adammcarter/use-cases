/// Why a schema could not be made to stand alone.
enum SchemaInliningError: Error, Equatable {
  /// A `$ref` names a file that was not given.
  case missingDocument(String)

  /// A `$ref` points at a place the file does not have.
  case unresolvedPointer(String)

  /// A `$ref` leads back to itself, so it could never be copied in.
  case circular(String)
}
