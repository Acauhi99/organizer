defmodule OrganizerWeb.AccountLinkLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.SharedFinance

  describe "access" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/account-links")
    end

    test "renders index for authenticated users", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:ok, view, _html} = live(conn, ~p"/account-links")
      assert has_element?(view, "#account-links-list")
      assert has_element?(view, "#new-invite-btn")
    end
  end

  describe "index — list of active links" do
    setup %{conn: conn} do
      user_a = user_fixture()
      user_b = user_fixture()

      scope_a = user_scope_fixture(user_a)
      scope_b = user_scope_fixture(user_b)

      {:ok, invite} = SharedFinance.create_invite(scope_a)
      {:ok, link} = SharedFinance.accept_invite(scope_b, invite.token)

      %{
        conn: log_in_user(conn, user_a),
        user_a: user_a,
        user_b: user_b,
        link: link
      }
    end

    test "renders partner email for each active link", %{conn: conn, user_b: user_b, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links")

      assert has_element?(view, "#account-link-#{link.id}")
      assert has_element?(view, "#account-link-#{link.id}", user_b.email)
    end

    test "shows deactivate button for each link", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links")

      assert has_element?(view, "#deactivate-link-#{link.id}")
    end
  end

  describe "new_invite — create invite" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders create invite button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/account-links/invite")

      assert has_element?(view, "#create-invite-btn")
    end

    test "creates invite and shows copyable link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/account-links/invite")

      refute has_element?(view, "#invite-url")

      view |> element("#create-invite-btn") |> render_click()

      assert has_element?(view, "#invite-url")

      invite_url_text = view |> element("#invite-url") |> render()
      assert invite_url_text =~ "account-links/accept/"
    end
  end

  describe "deactivate link" do
    setup %{conn: conn} do
      user_a = user_fixture()
      user_b = user_fixture()

      scope_a = user_scope_fixture(user_a)
      scope_b = user_scope_fixture(user_b)

      {:ok, invite} = SharedFinance.create_invite(scope_a)
      {:ok, link} = SharedFinance.accept_invite(scope_b, invite.token)

      %{
        conn: log_in_user(conn, user_a),
        link: link
      }
    end

    test "deactivates a link and removes it from the list", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links")

      assert has_element?(view, "#account-link-#{link.id}")

      view |> element("#deactivate-link-#{link.id}") |> render_click()

      refute has_element?(view, "#account-link-#{link.id}")
    end
  end
end
