import UseCasesCore

extension ResolvedLink {
  /// Its role, with the route of a validation link: `implementation`, `validation unit-tests`.
  var roleListing: String {
    guard let route else {
      return role.rawValue
    }

    return "\(role.rawValue) \(route)"
  }

  /// Its file and lines: `src/pay.swift:5` for one line, `src/pay.swift:5-9` for several.
  var placeListing: String {
    guard startLine != endLine else {
      return "\(file):\(startLine)"
    }

    return "\(file):\(startLine)-\(endLine)"
  }
}
