/// A file glob written from the workspace root: `*` and `?` stay inside one folder name, and a
/// `**` folder name stands for any number of folders, none included.
struct GlobPattern: Equatable, Sendable {
  private let segments: [Substring]

  init(_ pattern: String) {
    segments = pattern.split(
      separator: "/",
      omittingEmptySubsequences: true,
    )
  }

  func matches(_ path: String) -> Bool {
    let parts = path.split(
      separator: "/",
      omittingEmptySubsequences: true,
    )

    return GlobPattern.match(
      segments[...],
      parts[...],
    )
  }

  private static func match(
    _ pattern: ArraySlice<Substring>,
    _ path: ArraySlice<Substring>,
  ) -> Bool {
    guard let head = pattern.first else {
      return path.isEmpty
    }

    if head == "**" {
      let rest = pattern.dropFirst()

      return (0 ... path.count).contains { skipped in
        match(
          rest,
          path.dropFirst(skipped),
        )
      }
    }

    guard let name = path.first else {
      return false
    }

    guard matchesName(
      head,
      name,
    ) else {
      return false
    }

    return match(
      pattern.dropFirst(),
      path.dropFirst(),
    )
  }

  private static func matchesName(
    _ pattern: Substring,
    _ name: Substring,
  ) -> Bool {
    matchCharacters(
      Array(pattern),
      Array(name),
    )
  }

  private static func matchCharacters(
    _ pattern: [Character],
    _ name: [Character],
  ) -> Bool {
    var patternIndex = 0
    var nameIndex = 0
    var starIndex: Int?
    var resumeIndex = 0

    while nameIndex < name.count {
      if patternIndex < pattern.count, pattern[patternIndex] == "*" {
        starIndex = patternIndex
        resumeIndex = nameIndex
        patternIndex += 1
      } else if patternIndex < pattern.count,
                pattern[patternIndex] == "?" || pattern[patternIndex] == name[nameIndex]
      {
        patternIndex += 1
        nameIndex += 1
      } else if let star = starIndex {
        patternIndex = star + 1
        resumeIndex += 1
        nameIndex = resumeIndex
      } else {
        return false
      }
    }

    return pattern[patternIndex...].allSatisfy { character in
      character == "*"
    }
  }
}
