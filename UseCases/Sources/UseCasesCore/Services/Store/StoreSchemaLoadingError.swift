/// Why a bundled store schema could not be loaded. The name is the file's.
enum StoreSchemaLoadingError: Error, Equatable {
  /// The build holds no copy of the file.
  case missing(String)

  /// The copy cannot be read as UTF-8 text.
  case unreadable(String)

  /// The copy is not JSON.
  case invalidJSON(String, JSONReadingError)

  /// The copy is JSON but not a schema the checker can run.
  case invalidSchema(String, SchemaCompilerError)
}
