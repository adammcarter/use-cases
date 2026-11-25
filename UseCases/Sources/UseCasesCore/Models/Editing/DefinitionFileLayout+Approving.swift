extension DefinitionFileLayout {
  /// The lines of the file with the `approved` field of one use case written as `block`: where
  /// it is when the use case has one, otherwise after the last line of the use case. Nothing else
  /// in the file changes.
  func settingApproval(
    of number: Int,
    to block: [String],
  ) -> [String] {
    let item = items[number]

    guard let approved = item.approved else {
      return Array(lines[..<item.contentEnd]) + block + Array(lines[item.contentEnd...])
    }

    return Array(lines[..<approved.lowerBound]) + block + Array(lines[approved.upperBound...])
  }
}
