/// Why a line or column is not a source position (positions count from 1).
enum SourcePositionError: Error, Equatable, Sendable {
  case lineBelowOne(Int)
  case columnBelowOne(Int)
}
