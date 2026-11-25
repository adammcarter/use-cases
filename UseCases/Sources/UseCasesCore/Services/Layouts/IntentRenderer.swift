import Foundation

/// Reads an intent: the one layout that needs no workspace.
public struct IntentRenderer: IntentRendering {
  private let reader: any AuthoredInputReading

  /// Makes the renderer.
  ///
  /// - Parameter workingDirectory: Where a relative path given to `--file` is read from.
  public init(workingDirectory: URL) {
    self.init(reader: AuthoredInputReader(workingDirectory: workingDirectory))
  }

  init(reader: any AuthoredInputReading) {
    self.reader = reader
  }

  public func intent(readingFrom argument: String) throws(LayoutRenderingError) -> IntentLayout {
    let input: AuthoredInput

    do {
      input = try reader.read(AuthoredInputSource(argument: argument))
    } catch {
      throw .input(message: error.message)
    }

    return try IntentLayout(authored: input)
  }
}
