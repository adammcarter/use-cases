import Foundation

/// One program to run to its end and bring back what it printed, for a caller outside the core
/// (the MCP tools run `use-cases` this way).
public struct CommandInvocation: Equatable, Sendable {
  /// The program and its arguments; the program is the first. No shell is involved.
  public let arguments: [String]

  /// The folder the program starts in.
  public let workingDirectory: URL

  /// The text the program reads as its standard input, from a file; `nil` gives it none
  /// (`/dev/null`).
  public let standardInput: String?

  /// A descriptor of this process, the read end of a pipe it holds the other end of open, that the
  /// program is handed as a lifeline (``ProcessLifeline``): when this process dies the pipe reaches
  /// its end, and a `use-cases` that holds the lifeline cancels as if it had been told to.
  /// `nil` hands it none.
  public let lifeline: Int32?

  /// Describes a program to run.
  public init(
    arguments: [String],
    workingDirectory: URL,
    standardInput: String? = nil,
    lifeline: Int32? = nil,
  ) {
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.standardInput = standardInput
    self.lifeline = lifeline
  }
}
