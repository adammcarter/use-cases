import Foundation

extension String {
  /// Whether the two spellings differ only in letter case or Unicode form: what a case-insensitive
  /// or normalising file system would take for one name. Equal spellings are loosely equal too.
  func isLooselyEqual(to other: String) -> Bool {
    comparisonForm.isExactlyEqual(to: other.comparisonForm)
  }

  private var comparisonForm: String {
    decomposedStringWithCanonicalMapping.lowercased()
  }
}
