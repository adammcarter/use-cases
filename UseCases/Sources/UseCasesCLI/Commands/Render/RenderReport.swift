import Foundation
import UseCasesCore

/// What `use-cases render` prints (chapter 21 §7): the plain layout for a person, one JSON
/// document with the model and the plain text for scripts and agents.
struct RenderReport {
  private let layout: RenderedLayout
  private let style: LayoutStyle

  /// - Parameters:
  ///   - layout: The layout, drawn.
  ///   - style: How a person at a terminal sees its headers. A document never has it.
  init(
    layout: RenderedLayout,
    style: LayoutStyle,
  ) {
    self.layout = layout
    self.style = style
  }

  /// The layout, its headers in the style.
  func humanText() -> String {
    layout.text(style: style)
  }

  /// The document of `cli-render.schema.json`. Its text is plain: it is shown as it is in a chat,
  /// and escape codes would show.
  func jsonText() throws(RenderReportError) -> String {
    let document = StoreJSONValue.members([
      "output_version": .integer(OutputDocument.version),
      "command": .string(RenderCommand.name),
      "kind": .string(layout.kind.rawValue),
      "model": layout.model,
      "text": .string(layout.text(style: .plain)),
    ])

    guard let text = String(
      bytes: StoreJSONWriter().pretty(document),
      encoding: .utf8,
    ) else {
      throw .encodingFailed
    }

    return text
  }
}
