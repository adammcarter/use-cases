/// Why the report of `init` could not be written as a JSON document.
enum InitReportError: Error {
  case encodingFailed
}
