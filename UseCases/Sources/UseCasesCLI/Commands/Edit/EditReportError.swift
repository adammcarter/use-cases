/// Why the answer of `save` or `remove` could not be written as a JSON document.
enum EditReportError: Error {
  case encodingFailed
}
