import Foundation

/// Edits a definition file by its lines, so that one use case changes and every other line,
/// comment and blank line stays as it was.
struct DefinitionFileEditor: DefinitionFileEditing {
  let fileSystem: any FileSystemReading
  private let serialiser: any UseCaseSerialising
  let approvalSerialiser: any ApprovalSerialising
  private let scalarWriter: any YAMLScalarWriting
  private let yamlReader: any YAMLReading
  private let fileReader: any DefinitionFileReading

  init(
    fileSystem: any FileSystemReading = LocalFileSystem(),
    serialiser: any UseCaseSerialising = UseCaseSerialiser(),
    approvalSerialiser: any ApprovalSerialising = ApprovalSerialiser(),
    scalarWriter: any YAMLScalarWriting = YAMLScalarWriter(),
    yamlReader: any YAMLReading = StrictYAMLReader(),
    fileReader: any DefinitionFileReading = DefinitionFileReader(),
  ) {
    self.fileSystem = fileSystem
    self.serialiser = serialiser
    self.approvalSerialiser = approvalSerialiser
    self.scalarWriter = scalarWriter
    self.yamlReader = yamlReader
    self.fileReader = fileReader
  }

  func edit(
    _ edit: DefinitionFileEdit,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    switch edit {
    case let .create(file, prefix, definition):
      return try create(
        file,
        prefix: prefix,
        definition: definition,
      )
    case let .append(path, definition):
      return try append(
        definition,
        to: file(
          at: path,
          in: workspace,
        ),
      )
    case let .replace(identifier, definition):
      let (file, number) = try locate(
        identifier,
        in: workspace,
      )

      return try replace(
        number,
        of: file,
        with: definition,
        called: identifier.text,
      )
    case let .remove(identifier):
      let (file, number) = try locate(
        identifier,
        in: workspace,
      )

      return try remove(
        number,
        of: file,
        called: identifier.text,
      )
    case let .approve(identifier, approval):
      let (file, number) = try locate(
        identifier,
        in: workspace,
      )

      return try approve(
        number,
        of: file,
        with: approval,
        called: identifier.text,
      )
    }
  }

  // MARK: - The five edits

  private func create(
    _ path: WorkspacePath,
    prefix: Namespace,
    definition: UseCaseDefinition,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let lines = [
      "prefix: " + scalarWriter.text(
        of: prefix.text,
        in: .block,
      ),
      "use_cases:",
    ] + serialiser.itemLines(
      of: definition,
      writing: definition.localIdentifier.text,
      indent: Self.defaultIndent,
    )
    let text = lines.joined(separator: "\n") + "\n"

    try confirm(
      text,
      at: path,
      prefix: prefix,
      useCases: [definition],
    )

    return EditedDefinitionFile(
      change: .create(
        path,
        text: text,
      ),
      droppedComments: [],
    )
  }

  private func append(
    _ definition: UseCaseDefinition,
    to file: EditableFile,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let lines = file.layout.appending(
      serialiser.itemLines(
        of: definition,
        writing: definition.localIdentifier.text,
        indent: file.layout.itemIndent,
      ),
    )

    return try written(
      lines,
      of: file,
      useCases: file.original.useCases + [definition],
      dropped: [],
    )
  }

  private func replace(
    _ number: Int,
    of file: EditableFile,
    with definition: UseCaseDefinition,
    called identifier: String,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let lines = file.layout.replacing(
      number,
      with: serialiser.itemLines(
        of: definition,
        writing: definition.localIdentifier.text,
        indent: file.layout.itemIndent,
      ),
    )

    var useCases = file.original.useCases
    useCases[number] = definition

    return try written(
      lines,
      of: file,
      useCases: useCases,
      dropped: file.layout.items[number].innerComments.map { comment in
        file.droppedWarning(
          comment,
          because: "\(identifier) is rewritten whole",
        )
      },
    )
  }

  private func remove(
    _ number: Int,
    of file: EditableFile,
    called identifier: String,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let item = file.layout.items[number]

    guard file.layout.items.count > 1 else {
      return EditedDefinitionFile(
        change: .delete(
          file.path,
          expected: file.bytes,
        ),
        droppedComments: file.layout.comments.map { comment in
          file.droppedWarning(
            comment,
            because: "\(file.path.text) goes with \(identifier), its last use case",
          )
        },
      )
    }

    var useCases = file.original.useCases
    useCases.remove(at: number)

    return try written(
      file.layout.removing(number),
      of: file,
      useCases: useCases,
      dropped: (item.leadingComments + item.innerComments).map { comment in
        file.droppedWarning(
          comment,
          because: "it went with \(identifier)",
        )
      },
    )
  }

  // MARK: - Reading and checking

  func written(
    _ lines: [String],
    of file: EditableFile,
    useCases: [UseCaseDefinition],
    dropped: [String],
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let text = file.layout.text(of: lines)

    try confirm(
      text,
      at: file.path,
      prefix: file.original.prefix,
      useCases: useCases,
    )

    return EditedDefinitionFile(
      change: FileChange(
        action: .replace,
        path: file.path,
        bytes: Array(text.utf8),
        expected: file.bytes,
      ),
      droppedComments: dropped,
    )
  }

  /// Reads the text back as every definition file is read, and requires exactly the prefix and
  /// the use cases that were meant: the neighbours of the use case that changed included.
  private func confirm(
    _ text: String,
    at path: WorkspacePath,
    prefix: Namespace?,
    useCases: [UseCaseDefinition],
  ) throws(UseCaseEditingError) {
    let read = try definitionFile(
      text,
      at: path,
    )

    guard read.prefix == prefix, read.useCases == useCases else {
      throw .wouldNotReadBack(file: path.text)
    }
  }

  func definitionFile(
    _ text: String,
    at path: WorkspacePath,
  ) throws(UseCaseEditingError) -> DefinitionFile {
    do {
      return try fileReader.read(
        yamlReader.read(
          text,
          file: path.text,
          kind: .useCase,
        ),
        file: path,
      )
    } catch {
      throw .wouldNotReadBack(file: path.text)
    }
  }

  private static let defaultIndent = 2
}
