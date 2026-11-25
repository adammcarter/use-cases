/// Why the recorded run could not be written as a JSON document.
enum RecordReportError: Error {
  case encodingFailed
}
