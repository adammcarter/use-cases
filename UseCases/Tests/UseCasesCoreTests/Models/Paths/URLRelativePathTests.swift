import Foundation
import Testing
@testable import UseCasesCore

struct URLRelativePathTests {
  @Test(arguments: [
    ("/work/repo", "/work/repo", "."),
    ("/work/repo/.git/hooks", "/work/repo", ".git/hooks"),
    ("/work/repo/services/pay", "/work/repo", "services/pay"),
    ("/work/repo/.git/hooks", "/work/repo/services/pay", "../../.git/hooks"),
    ("/work/repo", "/work/repo/services/pay", "../.."),
    ("/elsewhere/modules/hooks", "/work/repo", "../../elsewhere/modules/hooks"),
    ("/work/repository", "/work/repo", "../repository"),
    ("/work", "/", "work"),
    ("/", "/", "."),
  ])
  func `the path from one folder to another climbs only as far as it must`(
    target: String,
    base: String,
    path: String,
  ) {
    #expect(URL(fileURLWithPath: target).relativePath(from: URL(fileURLWithPath: base)) == path)
  }
}
