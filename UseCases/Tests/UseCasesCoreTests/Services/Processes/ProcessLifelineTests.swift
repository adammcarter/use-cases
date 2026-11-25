import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct ProcessLifelineTests {
  @Test
  func `a lifeline is whole while the program that holds the other end lives`() throws {
    let pipe = TestPipe()
    defer {
      pipe.closeReadEnd()
      pipe.closeWriteEnd()
    }

    let lifeline = try #require(ProcessLifeline(descriptor: pipe.readEnd))

    #expect(!lifeline.isBroken)
    #expect(!lifeline.isBroken)
  }

  @Test
  func `a lifeline is broken once the other end is closed, and stays broken`() async throws {
    let pipe = TestPipe()
    defer {
      pipe.closeReadEnd()
    }
    let lifeline = try #require(ProcessLifeline(descriptor: pipe.readEnd))

    pipe.closeWriteEnd()
    await pipe.writersGone()

    #expect(lifeline.isBroken)
    #expect(lifeline.isBroken)
  }

  @Test
  func `the environment names the lifeline by the descriptor of a pipe`() async {
    let pipe = TestPipe()
    defer {
      pipe.closeReadEnd()
    }

    let lifeline = ProcessLifeline(environment: [ProcessLifeline.variable: "\(pipe.readEnd)"])

    #expect(lifeline != nil)
    pipe.closeWriteEnd()
    await pipe.writersGone()
    #expect(lifeline?.isBroken == true)
  }

  @Test(arguments: [nil, "", "x", "-1", "1.5", "9999"])
  func `an environment that names no open descriptor holds no lifeline`(text: String?) {
    var environment = ["PATH": "/usr/bin"]
    environment[ProcessLifeline.variable] = text

    #expect(ProcessLifeline(environment: environment) == nil)
  }

  @Test
  func `a descriptor that is not a pipe is no lifeline, whatever the environment says`() {
    let file = open("/dev/null", O_RDONLY)
    defer {
      close(file)
    }

    #expect(ProcessLifeline(descriptor: file) == nil)
    #expect(ProcessLifeline(environment: [ProcessLifeline.variable: "\(file)"]) == nil)
    #expect(ProcessLifeline(descriptor: -1) == nil)
  }

  @Test
  func `the descriptor a program is handed it as is the third, and the variable is named for it`() {
    #expect(ProcessLifeline.descriptor == 3)
    #expect(ProcessLifeline.variable == "USE_CASES_LIFELINE_FD")
  }
}
