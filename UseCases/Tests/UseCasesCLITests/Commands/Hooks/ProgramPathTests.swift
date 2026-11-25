import Foundation
import Testing
@testable import UseCasesCLI

struct ProgramPathTests {
  private static let folder = URL(fileURLWithPath: "/work/repo")

  private func path(
    _ command: String,
    searchPath: String? = nil,
    executable: Set<String> = [],
  ) -> String {
    ProgramPath(
      command: command,
      workingDirectory: Self.folder,
      searchPath: searchPath,
      isExecutable: { candidate in
        executable.contains(candidate)
      },
    ).text
  }

  @Test
  func `a full path is the path as it was run, with its links kept`() {
    #expect(path("/opt/homebrew/bin/use-cases") == "/opt/homebrew/bin/use-cases")
    #expect(path("/usr/local/bin/use-cases") == "/usr/local/bin/use-cases")
  }

  @Test(arguments: [
    ("./build/use-cases", "/work/repo/build/use-cases"),
    ("build/use-cases", "/work/repo/build/use-cases"),
    ("../tools/use-cases", "/work/repo/../tools/use-cases"),
    ("/opt//bin/./use-cases", "/opt/bin/use-cases"),
  ])
  func `a path with a slash is made absolute from where it was run`(
    command: String,
    expected: String,
  ) {
    #expect(path(command) == expected)
  }

  @Test
  func `a bare name is the first folder of the PATH that has it`() {
    #expect(
      path(
        "use-cases",
        searchPath: "/usr/bin:/opt/bin:/usr/local/bin",
        executable: ["/opt/bin/use-cases", "/usr/local/bin/use-cases"],
      ) == "/opt/bin/use-cases",
    )
  }

  @Test
  func `a folder of the PATH that is relative is read from where it was run`() {
    #expect(
      path(
        "use-cases",
        searchPath: "bin:",
        executable: ["/work/repo/bin/use-cases"],
      ) == "/work/repo/bin/use-cases",
    )
  }

  @Test(arguments: [nil, "", "/usr/bin"])
  func `a bare name that no folder has is left as a path from where it was run`(
    searchPath: String?,
  ) {
    #expect(path("use-cases", searchPath: searchPath) == "/work/repo/use-cases")
  }
}
