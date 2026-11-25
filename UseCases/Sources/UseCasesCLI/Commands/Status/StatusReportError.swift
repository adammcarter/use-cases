/// Why the status could not be written as a JSON document.
enum StatusReportError: Error {
  case encodingFailed
}
