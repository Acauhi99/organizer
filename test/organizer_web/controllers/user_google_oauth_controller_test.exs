defmodule OrganizerWeb.UserGoogleOAuthControllerTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures

  alias Organizer.Accounts

  setup do
    previous_client = Application.get_env(:organizer, :google_oauth_client)
    Application.put_env(:organizer, :google_oauth_client, OrganizerWeb.FakeGoogleOAuthClient)

    on_exit(fn ->
      if previous_client do
        Application.put_env(:organizer, :google_oauth_client, previous_client)
      else
        Application.delete_env(:organizer, :google_oauth_client)
      end

      Process.delete(:google_authorize_url_result)
      Process.delete(:google_userinfo_result)
    end)

    :ok
  end

  describe "GET /users/auth/google" do
    test "redirects to Google auth URL and stores oauth state", %{conn: conn} do
      conn = get(conn, ~p"/users/auth/google")

      assert redirected_to(conn, 302) ==
               "https://accounts.google.test/o/oauth2/v2/auth?state=fake-state"

      assert is_binary(get_session(conn, :google_oauth_state))
      assert is_binary(get_session(conn, :google_oauth_code_verifier))

      assert_received {:google_authorize_url_requested, opts}
      assert opts[:redirect_uri] == "http://localhost:4002/users/auth/google/callback"
      assert is_binary(opts[:state])
      assert is_binary(opts[:code_challenge])
    end

    test "shows error when Google OAuth is not configured", %{conn: conn} do
      Process.put(:google_authorize_url_result, {:error, :missing_configuration})

      conn = get(conn, ~p"/users/auth/google")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "ainda não está configurado"
    end
  end

  describe "GET /users/auth/google/callback" do
    test "creates a user and logs in with Google profile", %{conn: conn} do
      Process.put(
        :google_userinfo_result,
        {:ok,
         %{
           email: "new-google-user@example.com",
           email_verified: true,
           sub: "google-sub-123456789"
         }}
      )

      conn =
        conn
        |> init_test_session(%{
          google_oauth_state: "state-123",
          google_oauth_code_verifier: "verifier-123"
        })
        |> get(~p"/users/auth/google/callback?state=state-123&code=oauth-code-1")

      assert redirected_to(conn) == ~p"/finances"
      assert get_session(conn, :user_token)

      user = Accounts.get_user_by_email("new-google-user@example.com")
      assert user.google_sub == "google-sub-123456789"
      assert user.confirmed_at

      assert_received {:google_userinfo_requested, request}
      assert request.code == "oauth-code-1"
      assert request.code_verifier == "verifier-123"
    end

    test "links Google account to existing local user by email", %{conn: conn} do
      existing_user = user_fixture(email: "existing-google-link@example.com")

      Process.put(
        :google_userinfo_result,
        {:ok,
         %{
           email: existing_user.email,
           email_verified: true,
           sub: "google-sub-link-998877"
         }}
      )

      conn =
        conn
        |> init_test_session(%{
          google_oauth_state: "state-link",
          google_oauth_code_verifier: "verifier-link"
        })
        |> get(~p"/users/auth/google/callback?state=state-link&code=oauth-code-2")

      assert redirected_to(conn) == ~p"/finances"
      assert get_session(conn, :user_token)

      linked_user = Accounts.get_user!(existing_user.id)
      assert linked_user.google_sub == "google-sub-link-998877"
    end

    test "rejects callback with invalid state", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{
          google_oauth_state: "expected-state",
          google_oauth_code_verifier: "expected-verifier"
        })
        |> get(~p"/users/auth/google/callback?state=other-state&code=oauth-code-3")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "inválida"
      refute get_session(conn, :user_token)
      refute get_session(conn, :google_oauth_state)
      refute get_session(conn, :google_oauth_code_verifier)
    end

    test "rejects unverified Google email", %{conn: conn} do
      Process.put(
        :google_userinfo_result,
        {:ok,
         %{
           email: "unverified@example.com",
           email_verified: false,
           sub: "google-sub-unverified-1"
         }}
      )

      conn =
        conn
        |> init_test_session(%{
          google_oauth_state: "state-unverified",
          google_oauth_code_verifier: "verifier-unverified"
        })
        |> get(~p"/users/auth/google/callback?state=state-unverified&code=oauth-code-4")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "precisa estar verificado"
      refute get_session(conn, :user_token)
    end

    test "shows conflict message when email is linked to another Google account", %{conn: conn} do
      {:ok, _linked} =
        Accounts.find_or_create_user_by_google(%{
          email: "google-conflict@example.com",
          google_sub: "google-sub-original-111"
        })

      Process.put(
        :google_userinfo_result,
        {:ok,
         %{
           email: "google-conflict@example.com",
           email_verified: true,
           sub: "google-sub-other-222"
         }}
      )

      conn =
        conn
        |> init_test_session(%{
          google_oauth_state: "state-conflict",
          google_oauth_code_verifier: "verifier-conflict"
        })
        |> get(~p"/users/auth/google/callback?state=state-conflict&code=oauth-code-5")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "já está vinculado"
      refute get_session(conn, :user_token)
    end
  end
end
