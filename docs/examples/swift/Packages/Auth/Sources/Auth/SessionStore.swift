struct Session {
    let userID: String
}

final class SessionStore {
    private(set) var sessions: [Session] = []

    // @use-case:shop.auth.login.authenticate#session-creation
    func createSession(for user: User) -> Session {
        let session = Session(userID: user.id)
        sessions.append(session)
        return session
    }
    // @use-case:end shop.auth.login.authenticate#session-creation
}
