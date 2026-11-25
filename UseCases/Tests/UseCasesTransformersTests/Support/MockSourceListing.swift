@testable import UseCasesTransformers

/// A listing that answers with the files it was given, whatever is asked.
struct MockSourceListing: SourceListing {
  let listed: [String]

  func files(
    matching _: String,
    under _: String,
  ) -> [String] {
    listed
  }

  func files(directlyIn _: String) -> [String] {
    listed
  }
}
