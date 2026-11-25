extension SchemaFailure {
  /// Whether this is the schema refusing fields that name code or tools and nothing else, which
  /// the technical-field check has already reported in its own words.
  var isOnlyTechnicalFields: Bool {
    guard keyword == .additionalProperties else {
      return false
    }

    // The message names the refused fields between quotes: `('runner', 'command' were unexpected)`.
    let names = message.split(
      separator: "'",
      omittingEmptySubsequences: false,
    ).enumerated().filter { offset, _ in
      offset % 2 == 1
    }.map { _, name in
      String(name)
    }

    return !names.isEmpty
      && names.allSatisfy { name in
        TechnicalFieldChecker.technicalFields.contains { field in
          field.isExactlyEqual(to: name)
        }
      }
  }
}
