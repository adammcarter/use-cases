function submitLogin(username, password) {
  // @use-case:legacyapp.auth.login#login-submit-ui
  return fetch("/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
    headers: { "Content-Type": "application/json" }
  });
  // @use-case:end legacyapp.auth.login#login-submit-ui
}
