extension DiagnosticCode {
  /// A route's resource file is not there.
  static let resourceFileMissing: DiagnosticCode = "resource-file-missing"

  /// A route's resource file is spelled differently on disk.
  static let resourceFileSpelledDifferently: DiagnosticCode = "resource-file-spelled-differently"

  /// A route's resource file path passes through a symlink, which is never followed.
  static let resourceFileBehindSymlink: DiagnosticCode = "resource-file-behind-symlink"

  /// A route's resource file is a folder, or a pipe, socket or device.
  static let resourceFileNotAFile: DiagnosticCode = "resource-file-not-a-file"

  /// A route's resource file, or a folder on the way to it, cannot be read.
  static let resourceFileUnreadable: DiagnosticCode = "resource-file-unreadable"

  /// A route's resource glob matches no file the code scan reads.
  static let resourceGlobMatchesNothing: DiagnosticCode = "resource-glob-matches-nothing"

  /// A route's explicit resource file is in excluded content: allowed, with a warning.
  static let resourceIntoExcludedContent: DiagnosticCode = "resource-into-excluded-content"

  /// A file a link points into cannot be read when the route is fingerprinted.
  static let linkedFileUnreadable: DiagnosticCode = "linked-file-unreadable"

  /// A file a link points into no longer holds the link's region.
  static let linkedRegionOutsideFile: DiagnosticCode = "linked-region-outside-file"

  /// A route's parts do not fit together, which resolution should have refused.
  static let routeNotFingerprintable: DiagnosticCode = "route-not-fingerprintable"
}
