import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct GlobalOptionsTests {
  private let here = URL(fileURLWithPath: "/work/shop")

  private func options(_ arguments: [String]) throws -> GlobalOptions {
    try GlobalOptions.parse(arguments)
  }

  @Test
  func `without a workspace it searches upward from where it is`() throws {
    #expect(try options([]).start(from: here) == .searchingUpward(from: here))
  }

  @Test
  func `an absolute workspace is the root itself`() throws {
    let start = try options(["--workspace", "/elsewhere/shop"]).start(from: here)

    #expect(start == .workspace(URL(fileURLWithPath: "/elsewhere/shop")))
  }

  @Test
  func `a relative workspace is read from where it is`() throws {
    let start = try options(["--workspace", "../other"]).start(from: here)

    #expect(start == .workspace(URL(fileURLWithPath: "/work/other")))
  }

  @Test
  func `the folder is where it is unless a workspace names one`() throws {
    #expect(try options([]).folder(from: here) == here)
    #expect(try options(["--workspace", "../other"]).folder(from: here)
      == URL(fileURLWithPath: "/work/other"))
    #expect(try options(["--workspace", "/elsewhere"]).folder(from: here)
      == URL(fileURLWithPath: "/elsewhere"))
  }

  @Test
  func `json is off unless it is given`() throws {
    #expect(try !options([]).json)
    #expect(try options(["--json"]).json)
  }

  @Test
  func `the hint is shown unless quiet is given`() throws {
    #expect(try !options([]).quiet)
    #expect(try options(["--quiet"]).quiet)
  }
}
