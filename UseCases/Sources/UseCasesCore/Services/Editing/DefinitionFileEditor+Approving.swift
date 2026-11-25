extension DefinitionFileEditor {
  func approve(
    _ number: Int,
    of file: EditableFile,
    with approval: Approval,
    called identifier: String,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let item = file.layout.items[number]

    guard let indent = item.fieldIndent else {
      throw .unsupportedLayout(
        file: file.path.text,
        reason: "\(identifier) is not written as a block mapping, so its sign-off cannot be "
          + "written into its lines",
      )
    }

    var useCases = file.original.useCases
    useCases[number] = useCases[number].approved(approval)

    return try written(
      file.layout.settingApproval(
        of: number,
        to: approvalSerialiser.lines(
          of: approval,
          indent: indent,
        ),
      ),
      of: file,
      useCases: useCases,
      dropped: item.innerComments.filter { comment in
        item.approved?.contains(comment.line - 1) == true
      }.map { comment in
        file.droppedWarning(
          comment,
          because: "the sign-off of \(identifier) is written again",
        )
      },
    )
  }
}
