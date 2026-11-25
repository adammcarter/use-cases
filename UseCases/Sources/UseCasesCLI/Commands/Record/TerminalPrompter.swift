import Foundation

/// Talks to the person through standard output and standard input.
struct TerminalPrompter: Prompting {
  func show(_ text: String) async {
    write(text + "\n")
  }

  /// Reading stops the thread until a line is typed: the command is waiting for the person and
  /// has nothing else to do.
  func ask(_ question: String) async -> String? {
    write(question)

    return readLine()
  }

  /// Written to the descriptor at once, so a question is on the screen before the wait for its
  /// answer begins.
  private func write(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }
}
