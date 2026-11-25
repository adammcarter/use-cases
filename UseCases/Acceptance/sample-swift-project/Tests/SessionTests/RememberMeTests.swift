import Testing
@testable import Auth

struct RememberMeTests {
    // @use-case:shop.login.remember-me#unit-tests.persists-session
    @Test func persistsSession() {
        #expect(LoginService().rememberSession(for: User(id: "user-1")) == "session-user-1")
    }
    // @use-case:end shop.login.remember-me#unit-tests.persists-session
}
