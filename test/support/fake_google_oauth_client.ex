defmodule OrganizerWeb.FakeGoogleOAuthClient do
  def build_authorize_url(opts) do
    send(self(), {:google_authorize_url_requested, opts})

    Process.get(:google_authorize_url_result) ||
      {:ok, "https://accounts.google.test/o/oauth2/v2/auth?state=fake-state"}
  end

  def fetch_userinfo(code, code_verifier, redirect_uri) do
    send(
      self(),
      {:google_userinfo_requested,
       %{code: code, code_verifier: code_verifier, redirect_uri: redirect_uri}}
    )

    Process.get(:google_userinfo_result) ||
      {:ok,
       %{
         email: "google-user@example.com",
         email_verified: true,
         sub: "google-sub-default-12345"
       }}
  end
end
