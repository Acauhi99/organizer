defmodule OrganizerWeb.AccountLinkControllerTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures

  alias Organizer.SharedFinance

  describe "GET /account-links/accept/:token" do
    test "redirects unauthenticated users to log in and preserves return path", %{conn: conn} do
      conn = get(conn, ~p"/account-links/accept/token-123")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == "/account-links/accept/token-123"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Faça login"
    end

    test "accepts invite for authenticated users and redirects to shared finance", %{conn: conn} do
      inviter = user_fixture()
      acceptor = user_fixture()

      inviter_scope = user_scope_fixture(inviter)
      acceptor_scope = user_scope_fixture(acceptor)

      {:ok, invite} = SharedFinance.create_invite(inviter_scope)

      conn =
        conn
        |> log_in_user(acceptor)
        |> get(~p"/account-links/accept/#{invite.token}")

      {:ok, [link]} = SharedFinance.list_account_links(acceptor_scope)

      assert redirected_to(conn) == ~p"/account-links/#{link.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Compartilhamento estabelecido"
    end

    test "shows error when invite is invalid", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/account-links/accept/invalid-token")

      assert redirected_to(conn) == ~p"/account-links/invite"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Convite inválido"
    end
  end
end
