import Foundation
import Testing
@testable import UseCasesCore

struct FlockStoreLockTests {
  private let directory: TemporaryDirectory
  private let lock = FlockStoreLock()

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func take(_ file: URL) throws {
    try lock.locked(at: file) { () throws(StoreWritingError) in
      // Nothing to do while it is held.
    }
  }

  @Test
  func `the body runs and its value comes back`() throws {
    let value = try lock
      .locked(at: directory.location(of: "allocation.lock")) { () throws(StoreWritingError) in
        42
      }

    #expect(value == 42)
  }

  @Test
  func `the lock is let go when the body ends, so it can be taken again`() throws {
    let file = directory.location(of: "allocation.lock")

    try take(file)
    try take(file)
    try take(file)
  }

  @Test
  func `the lock is let go when the body throws`() throws {
    let file = directory.location(of: "allocation.lock")

    #expect(throws: StoreWritingError.identifiersExhausted) {
      try lock.locked(at: file) { () throws(StoreWritingError) in
        throw .identifiersExhausted
      }
    }

    try lock.locked(at: file) { () throws(StoreWritingError) in }
  }

  @Test
  func `a lock file that cannot be opened is an error`() {
    #expect(throws: StoreWritingError.self) {
      try lock
        .locked(at: directory
          .location(of: "missing/allocation.lock")) { () throws(StoreWritingError) in }
    }
  }

  @Test
  func `a lock file that is a symlink is not followed`() throws {
    let target = directory.location(of: "elsewhere")
    try Data().write(to: target)
    try directory.symlink("allocation.lock", to: target.path)

    #expect(throws: StoreWritingError.self) {
      try lock
        .locked(at: directory.location(of: "allocation.lock")) { () throws(StoreWritingError) in
          // Not reached.
        }
    }
  }

  @Test
  func `two holders in one process never hold the lock together`() async {
    let file = directory.location(of: "allocation.lock")
    let marker = directory.location(of: "inside")
    let lock = lock
    let files = LocalStoreFileWriter()

    // A holder makes a marker that only one can make at a time. A holder that gets in while
    // another is inside cannot make it, and says so.
    let alone = await withTaskGroup(of: Bool.self) { group in
      for _ in 0 ..< 8 {
        group.addTask {
          let held: Void? = try? lock.locked(at: file) { () throws(StoreWritingError) in
            try files.createFile(
              [],
              at: marker,
            )
            files.discard(marker)
          }

          return held != nil
        }
      }

      var found: [Bool] = []
      for await result in group {
        found.append(result)
      }

      return found
    }

    #expect(alone.count == 8)
    #expect(!alone.contains(false))
  }
}
