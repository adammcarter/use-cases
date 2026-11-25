#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A pipe of this process, whose ends a test closes when it chooses.
struct TestPipe {
  let readEnd: Int32
  let writeEnd: Int32

  init() {
    var ends: [Int32] = [-1, -1]
    pipe(&ends)
    readEnd = ends[0]
    writeEnd = ends[1]
  }

  func closeReadEnd() {
    close(readEnd)
  }

  func closeWriteEnd() {
    close(writeEnd)
  }
}
