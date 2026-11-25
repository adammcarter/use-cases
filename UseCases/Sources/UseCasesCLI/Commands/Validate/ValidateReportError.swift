/// Why the validation report could not be written as a JSON document.
enum ValidateReportError: Error {
  case encodingFailed
}
