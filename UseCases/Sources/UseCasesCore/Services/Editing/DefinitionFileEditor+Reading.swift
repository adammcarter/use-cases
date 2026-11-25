import Foundation

extension DefinitionFileEditor {
  /// The file a use case of the workspace is written in, and which of its use cases it is.
  func locate(
    _ identifier: UseCaseIdentifier,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> (EditableFile, Int) {
    guard let useCase = workspace.useCases.first(where: { $0.identifier == identifier }) else {
      throw .unknown(identifier: identifier.text)
    }

    let file = try file(
      at: useCase.file,
      in: workspace,
    )

    guard
      let number = file.original.useCases.firstIndex(where: { definition in
        definition.localIdentifier == useCase.definition.localIdentifier
      })
    else {
      throw .unsupportedLayout(
        file: useCase.file.text,
        reason: "\(identifier.text) is not in it",
      )
    }

    return (file, number)
  }

  func file(
    at path: WorkspacePath,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> EditableFile {
    let bytes: [UInt8]

    do {
      bytes = try fileSystem.readBytes(at: workspace.root.appendingPathComponent(path.text))
    } catch {
      throw .unreadable(
        file: path.text,
        reason: "\(error)",
      )
    }

    guard let decoded = String(bytes: bytes, encoding: .utf8) else {
      throw .unreadable(
        file: path.text,
        reason: "it is not UTF-8 text",
      )
    }

    // Foundation drops a leading byte order mark on some systems and keeps it on others. It is
    // always kept, so that the file is written back with it.
    let text = bytes.starts(with: [0xEF, 0xBB, 0xBF]) && decoded.unicodeScalars.first != "\u{FEFF}"
      ? "\u{FEFF}" + decoded : decoded

    let original = try definitionFile(
      text,
      at: path,
    )
    let layout: DefinitionFileLayout

    do {
      layout = try DefinitionFileLayout(text: text)
    } catch {
      throw .unsupportedLayout(
        file: path.text,
        reason: error.message,
      )
    }

    guard layout.items.count == original.useCases.count else {
      throw .unsupportedLayout(
        file: path.text,
        reason: "its use cases are not written one to a `- `",
      )
    }

    return EditableFile(
      path: path,
      layout: layout,
      original: original,
      bytes: bytes,
    )
  }
}
