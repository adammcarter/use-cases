import Foundation
import os

/// Where a child process's stderr goes when it is not passed straight through
/// to this process's own: collected, in order, so a caller that buffers its
/// output (the CLI) can emit it where node's inherited stderr would have put it.
public final class ProcessStandardErrorLog: Sendable {
  private let bytes = OSAllocatedUnfairLock(initialState: Data())

  public init() {}

  /// Append a chunk of stderr.
  public func append(_ data: Data) {
    bytes.withLock { collected in
      collected.append(data)
    }
  }

  /// Append text, as a process writing to stderr would.
  public func append(_ text: String) {
    append(Data(text.utf8))
  }

  /// Everything collected so far, decoded as UTF-8 with invalid bytes replaced.
  public var text: String {
    UTF8Text.decodeReplacingInvalid([UInt8](bytes.withLock { $0 }))
  }
}
