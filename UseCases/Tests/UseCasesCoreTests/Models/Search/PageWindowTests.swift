import Testing
@testable import UseCasesCore

struct PageWindowTests {
  @Test(arguments: [
    (0, 0, 20, 0 ..< 0, nil as Int?),
    (3, 0, 20, 0 ..< 3, nil),
    (3, 0, 1, 0 ..< 1, 1),
    (3, 2, 1, 2 ..< 3, nil),
    (40, 20, 20, 20 ..< 40, nil),
    (41, 20, 20, 20 ..< 40, 40),
    (5, 9, 2, 5 ..< 5, nil),
  ])
  func `a window shows its part of the list and says where the next begins`(
    total: Int,
    offset: Int,
    size: Int,
    range: Range<Int>,
    next: Int?,
  ) {
    let window = PageWindow(
      total: total,
      offset: offset,
      size: size,
    )

    #expect(window.range == range)
    #expect(window.nextOffset == next)
  }

  @Test
  func `a page holds 20 by default and 1 to 100`() {
    #expect(PageWindow.defaultSize == 20)
    #expect(PageWindow.sizes == 1 ... 100)
  }

  @Test(arguments: [
    ("1", 1), ("20", 20), ("100", 100), ("007", 7),
  ])
  func `a spelled size of 1 to 100 in ASCII digits is a size`(
    text: String,
    size: Int,
  ) {
    #expect(PageWindow.size(spelled: text) == size)
  }

  @Test(arguments: [
    "",
    "0",
    "101",
    "-1",
    "+1",
    "1.0",
    "1e1",
    "x",
    " 1",
    "١٢",
    "99999999999999999999"
  ])
  func `anything else is not a size`(text: String) {
    #expect(PageWindow.size(spelled: text) == nil)
  }
}
