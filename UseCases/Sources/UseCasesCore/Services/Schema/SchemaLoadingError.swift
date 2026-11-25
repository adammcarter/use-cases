/// Why a bundled schema could not be loaded.
enum SchemaLoadingError: Error, Equatable {
  /// The build holds no copy of the schema.
  case missing(AuthoredSchema)

  /// The copy cannot be read as UTF-8 text.
  case unreadable(AuthoredSchema)

  /// The copy is not JSON.
  case invalidJSON(AuthoredSchema, JSONReadingError)

  /// The copy is JSON but not a schema the checker can run.
  case invalidSchema(AuthoredSchema, SchemaCompilerError)
}
