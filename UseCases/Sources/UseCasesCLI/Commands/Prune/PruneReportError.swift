/// Why the report of `prune` could not be written as a JSON document.
enum PruneReportError: Error {
  case encodingFailed
}
