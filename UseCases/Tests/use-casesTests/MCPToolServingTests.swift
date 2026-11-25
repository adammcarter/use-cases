import Foundation
import Testing
import UseCasesCLI
import UseCasesCore
import UseCasesTestSupport
@testable import use_cases

struct MCPToolServingTests {
  @Test
  func `a use-cases that cannot find itself cannot run its tools, and says so`() async {
    let serving = MCPToolServing(executable: MockRunningExecutableLocating(at: nil))

    let ending = await serving.serve(
      workingDirectory: URL(fileURLWithPath: "/work"),
      workspace: nil,
      shutdown: MockCancellation.never,
    )

    #expect(
      ending == .failed(
        reason: "the running use-cases cannot be found, so it cannot run its tools",
      ),
    )
  }
}
