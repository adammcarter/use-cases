@testable import UseCasesCore

/// Reads the JSON text of a test into the value an authored file reads as.
func authored(_ json: String) throws -> AuthoredValue {
  try JSONReader().read(json)
}
