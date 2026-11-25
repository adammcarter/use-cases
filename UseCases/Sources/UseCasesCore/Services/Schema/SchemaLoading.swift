import Foundation

/// Finds the checker for each authored schema.
protocol SchemaLoading: Sendable {
  /// The checker for one of the four authored schemas.
  func loadChecker(for schema: AuthoredSchema) throws(SchemaLoadingError) -> any SchemaChecking
}
