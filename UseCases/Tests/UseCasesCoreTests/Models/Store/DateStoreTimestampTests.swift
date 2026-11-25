import Foundation
import Testing
@testable import UseCasesCore

struct DateStoreTimestampTests {
  @Test
  func `a time is written in UTC with milliseconds and a Z`() {
    #expect(FixedTimekeeper.sampleDate.storeTimestamp == "2026-09-25T12:34:56.123Z")
  }

  @Test
  func `a whole second keeps its three zeros`() {
    let date = Date(timeIntervalSince1970: 0)

    #expect(date.storeTimestamp == "1970-01-01T00:00:00.000Z")
  }

  @Test
  func `milliseconds are whole milliseconds since 1970`() {
    #expect(FixedTimekeeper.sampleDate.storeMilliseconds == 1_790_339_696_123)
  }

  @Test
  func `a time before 1970 has no milliseconds`() {
    let date = Date(timeIntervalSince1970: -5)

    #expect(date.storeMilliseconds == 0)
  }
}
