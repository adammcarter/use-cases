/// Why inputs cannot be fingerprinted. Each is a fault upstream, in what the core resolved, not
/// in the encoding.
enum FingerprintingError: Error, Equatable {
  case encoding(CanonicalEncodingError)

  /// The use case has no intent, which every route payload carries.
  case missingIntent

  /// Two covered scenarios have the same id.
  case duplicateScenario(String)

  /// A route covers a scenario that was not supplied.
  case coversWithoutScenario(String)

  /// A scenario was supplied that the route does not cover.
  case scenarioNotCovered(String)

  /// Two entries of one collection are for the same binding id.
  case duplicateBinding(String)

  /// A binding with no region: a link always holds at least one.
  case bindingWithoutRegions(String)

  /// One resource path arrived with two different contents.
  case conflictingResource(String)

  /// A region reaches past the end of the file's bytes.
  case regionOutsideFile(Range<Int>)
}
