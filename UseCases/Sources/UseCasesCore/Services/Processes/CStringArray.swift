import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A `NULL`-terminated array of C strings, the shape `argv` and `envp` have. It owns the copies
/// and gives them back with `release()`.
struct CStringArray {
  /// The copies, then a final `nil`.
  let pointers: [UnsafeMutablePointer<CChar>?]

  /// `nil` when a string cannot be copied.
  init?(_ strings: [String]) {
    var copies: [UnsafeMutablePointer<CChar>?] = []

    for string in strings {
      guard let copy = strdup(string) else {
        for earlier in copies {
          free(earlier)
        }

        return nil
      }

      copies.append(copy)
    }

    pointers = copies + [nil]
  }

  func release() {
    for pointer in pointers {
      free(pointer)
    }
  }
}
