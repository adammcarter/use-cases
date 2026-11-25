import MCP
@testable import UseCasesMCP

/// A keeper of arguments that keeps them in a list, and answers every one with the same key.
actor SpyToolCallArgumentHolding: ToolCallArgumentHolding {
  /// The arguments it was asked to keep, in order.
  private(set) var held: [Value] = []

  private let key: String

  init(answering key: String) {
    self.key = key
  }

  func hold(_ arguments: Value) -> String {
    held.append(arguments)

    return key
  }
}
