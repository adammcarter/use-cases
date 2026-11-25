/// Why the report of `hooks` could not be written as a JSON document.
enum HooksReportError: Error {
  case encodingFailed
}
