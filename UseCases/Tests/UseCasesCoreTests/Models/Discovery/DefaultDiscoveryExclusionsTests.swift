import Testing
@testable import UseCasesCore

struct DefaultDiscoveryExclusionsTests {
  private func isExcludedByDefault(_ path: WorkspacePath) -> Bool {
    DefaultDiscoveryExclusions.patterns.contains { pattern in
      pattern.excludes(path)
    }
  }

  @Test
  func `all six default patterns parse`() {
    #expect(DefaultDiscoveryExclusions.patterns.count == 6)
    #expect(DefaultDiscoveryExclusions.patterns.map(\.text) == DefaultDiscoveryExclusions
      .patternTexts)
  }

  @Test
  func `the defaults are exactly the store and the five history folders`() {
    #expect(
      DefaultDiscoveryExclusions.patternTexts == [
        "**/.use-cases/**", "**/.git/**", "**/.hg/**", "**/.svn/**", "**/.bzr/**", "**/.jj/**",
      ],
    )
  }

  @Test(
    arguments: [
      ".use-cases", ".use-cases/runs/a", ".git", ".git/objects", "a/.git", "a/b/.hg/x",
      "a/.svn", ".bzr/x", "x/y/.jj/z", "pkg/.use-cases/runs",
    ],
  )
  func `store and history folders are excluded at any depth`(text: String) throws {
    let path = try WorkspacePath(validating: text)

    #expect(isExcludedByDefault(path))
  }

  @Test(arguments: [
    "use-cases",
    "src",
    "git",
    ".github",
    ".gitignore",
    "a/use-cases",
    ".jj-x",
    "build",
  ])
  func `nothing else is excluded by default`(text: String) throws {
    let path = try WorkspacePath(validating: text)

    #expect(!isExcludedByDefault(path))
  }
}
