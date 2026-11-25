/// Why the answer of `docs` could not be written as a JSON document.
enum DocsReportError: Error {
  case encodingFailed
}
