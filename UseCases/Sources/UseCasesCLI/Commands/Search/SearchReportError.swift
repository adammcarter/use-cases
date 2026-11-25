/// Why the matches could not be written as a JSON document.
enum SearchReportError: Error {
  case encodingFailed
}
