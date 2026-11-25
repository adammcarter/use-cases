/// One name in a folder, and what it is on disk.
struct FileEntry: Equatable, Sendable {
  /// The name exactly as the file system spells it. A name that is not valid UTF-8 cannot be a
  /// `String`, so it is written here with every byte outside printable ASCII as `\xNN`, to be
  /// shown and never to be looked up.
  let name: String
  let kind: FileEntryKind

  /// Whether `name` is the name's own text. When it is not, no workspace path can spell it.
  let isNameUTF8: Bool

  /// The name's bytes, as the file system stores them.
  let nameBytes: [UInt8]

  /// The name as a message shows it: quoted, with anything unprintable escaped.
  var displayName: String {
    isNameUTF8 ? name.debugDescription : "\"\(name)\""
  }

  /// Makes an entry; a name is UTF-8 unless the file system says it is not. The bytes are the
  /// name's own UTF-8 unless given.
  init(
    name: String,
    kind: FileEntryKind,
    isNameUTF8: Bool = true,
    nameBytes: [UInt8]? = nil,
  ) {
    self.name = name
    self.kind = kind
    self.isNameUTF8 = isNameUTF8
    self.nameBytes = nameBytes ?? Array(name.utf8)
  }
}
