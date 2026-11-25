import Foundation
import Testing
@testable import UseCasesCore

struct ConsoleCaptureFileWholeTests {
  @Test(arguments: ["", "text", "caf\u{E9}\nline two\n", String(repeating: "x", count: 2_000_000)])
  func `what is filled in is what is read back whole, from the start`(text: String) throws {
    let capture = try ConsoleCaptureFile.create()
    defer {
      capture.release()
    }

    try capture.fill(with: text)

    #expect(try capture.readEverything() == text)
  }

  @Test
  func `bytes that are not text read as the replacement character, where they are`() throws {
    let capture = try ConsoleCaptureFile.create()
    defer {
      capture.release()
    }

    let bytes: [UInt8] = [0x61, 0xFF, 0x62]
    _ = write(capture.descriptor, bytes, bytes.count)

    #expect(try capture.readEverything() == "a\u{FFFD}b")
  }
}
