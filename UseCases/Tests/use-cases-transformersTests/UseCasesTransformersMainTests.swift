import Testing
import UseCasesTransformers
@testable import use_cases_transformers

struct UseCasesTransformersMainTests {
  @Test
  func `the executable runs the transformer program`() {
    // The built executable itself is proven by the acceptance suite's transformer tests.
    #expect(UseCasesTransformersMain.program == TransformerProgram())
  }
}
