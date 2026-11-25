import Foundation
import Testing
@testable import UseCasesMCP

struct ServerLifelineTests {
  @Test
  func `the lifeline is a pipe, its read end out of the way of the descriptors handed on`(
  ) throws {
    let lifeline = try ServerLifeline()
    defer {
      lifeline.close()
    }
    var information = stat()

    #expect(fstat(lifeline.readEnd, &information) == 0)
    #expect(information.st_mode & S_IFMT == S_IFIFO)
    #expect(lifeline.readEnd >= 10)
  }

  @Test
  func `neither end of the lifeline is inherited by a program that is not handed it`() throws {
    let lifeline = try ServerLifeline()
    defer {
      lifeline.close()
    }

    #expect(fcntl(lifeline.readEnd, F_GETFD) & FD_CLOEXEC != 0)
  }

  @Test
  func `the lifeline does not end while the server holds it, and ends when the server lets go`(
  ) throws {
    let lifeline = try ServerLifeline()
    // A reader of its own, so that closing the server's ends cannot hand the number to another.
    let reader = dup(lifeline.readEnd)
    defer {
      close(reader)
    }
    var watched = pollfd(fd: reader, events: Int16(POLLIN), revents: 0)

    #expect(poll(&watched, 1, 0) == 0)

    lifeline.close()

    #expect(poll(&watched, 1, 0) == 1)
    #expect(watched.revents & Int16(POLLHUP) != 0)
  }
}
