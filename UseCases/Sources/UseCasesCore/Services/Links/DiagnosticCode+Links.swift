extension DiagnosticCode {
  /// A well-paired marker names a use case that does not exist.
  static let markerUnknownUseCase: DiagnosticCode = "marker-unknown-use-case"

  /// A well-paired marker names a route its use case does not have.
  static let markerUnknownRoute: DiagnosticCode = "marker-unknown-route"

  /// A file the scan cannot read, so the links in it are unknown.
  static let unreadableFile: DiagnosticCode = "unreadable-file"

  /// A pipe, socket or device, which the scan never opens.
  static let specialFileSkipped: DiagnosticCode = "special-file-skipped"

  /// A file whose name no workspace path can spell, which the scan skips.
  static let unscannableName: DiagnosticCode = "unscannable-name"

  /// A manual binding names a file that is not there.
  static let bindingFileMissing: DiagnosticCode = "binding-file-missing"

  /// A manual binding's path passes through a symlink, which is never followed.
  static let bindingFileBehindSymlink: DiagnosticCode = "binding-file-behind-symlink"

  /// A manual binding spells a path differently from the disk.
  static let bindingFileSpelledDifferently: DiagnosticCode = "binding-file-spelled-differently"

  /// A manual binding names something that is not a file.
  static let bindingFileNotAFile: DiagnosticCode = "binding-file-not-a-file"

  /// A manual binding names a file, or a folder on the way to it, that cannot be read.
  static let bindingFileUnreadable: DiagnosticCode = "binding-file-unreadable"

  /// A manual binding's range does not fit its file.
  static let bindingRangeOutsideFile: DiagnosticCode = "binding-range-outside-file"

  /// A manual binding's range is cut from a file that is not text.
  static let bindingRangeNotText: DiagnosticCode = "binding-range-not-text"

  /// A manual binding points at a path discovery excludes.
  static let linkIntoExcludedContent: DiagnosticCode = "link-into-excluded-content"

  /// A whole-file manual binding names an empty file.
  static let emptyWholeFileBinding: DiagnosticCode = "empty-whole-file-binding"

  /// A manual range that selects no bytes.
  static let emptyBindingRange: DiagnosticCode = "empty-binding-range"

  /// One binding written in YAML and also marked in the code.
  static let bindingClaimedTwice: DiagnosticCode = "binding-claimed-twice"

  /// Two links with one link key.
  static let linkKeyShared: DiagnosticCode = "link-key-shared"

  /// Two links of one use case and role that cover some of the same bytes.
  static let overlappingLinks: DiagnosticCode = "overlapping-links"
}
