/// Why a value is not canonical JSON (chapter 11 §89.1). A string with an unpaired surrogate is
/// refused too, but a Swift string cannot hold one, so it needs no case.
enum CanonicalEncodingError: Error, Equatable {
  /// Two members of one object have the same key, compared by UTF-8 bytes.
  case duplicateKey(String)

  /// An integer outside -(2^53 - 1) through 2^53 - 1.
  case integerOutOfRange(Int)
}
