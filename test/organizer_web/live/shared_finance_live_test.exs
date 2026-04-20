defmodule OrganizerWeb.SharedFinanceLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.SharedFinance
  alias Organizer.Planning

  defp setup_linked_users do
    user_a = user_fixture()
    user_b = user_fixture()

    scope_a = user_scope_fixture(user_a)
    scope_b = user_scope_fixture(user_b)

    {:ok, invite} = SharedFinance.create_invite(scope_a)
    {:ok, link} = SharedFinance.accept_invite(scope_b, invite.token)

    %{user_a: user_a, user_b: user_b, scope_a: scope_a, scope_b: scope_b, link: link}
  end

  defp create_shared_entry(scope, link_id) do
    {:ok, entry} =
      Planning.create_finance_entry(scope, %{
        "description" => "Shared expense",
        "amount_cents" => 10_000,
        "kind" => "income",
        "category" => "Salário",
        "occurred_on" => Date.to_iso8601(Date.utc_today())
      })

    {:ok, updated_entry} = SharedFinance.share_finance_entry(scope, entry.id, link_id)
    updated_entry
  end

  describe "access" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/account-links/1")
    end

    test "redirects to account-links when link not found", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/account-links"}}} =
               live(conn, ~p"/account-links/999999")
    end
  end

  describe "renders shared entries list" do
    setup %{conn: conn} do
      %{user_a: user_a, scope_a: scope_a, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)
      %{conn: conn, scope_a: scope_a, link: link}
    end

    test "renders the shared entries list container", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")
      assert has_element?(view, "#shared-entries-list")
    end

    test "renders the metrics panel", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")
      assert has_element?(view, "#link-metrics-panel")
    end

    test "renders the recurring variable trend section", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")
      assert has_element?(view, "#recurring-variable-trend")
    end

    test "shows shared entry in the stream after sharing", %{
      conn: conn,
      scope_a: scope_a,
      link: link
    } do
      entry = create_shared_entry(scope_a, link.id)
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")
      assert has_element?(view, "#unshare-entry-#{entry.id}")
    end
  end

  describe "PubSub event updates listing without reload" do
    setup %{conn: conn} do
      %{user_a: user_a, scope_a: scope_a, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)
      %{conn: conn, scope_a: scope_a, link: link}
    end

    test "broadcast :shared_entry_updated refreshes the stream", %{
      conn: conn,
      scope_a: scope_a,
      link: link
    } do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")

      entry = create_shared_entry(scope_a, link.id)

      Phoenix.PubSub.broadcast(
        Organizer.PubSub,
        "account_link:#{link.id}",
        {:shared_entry_updated, entry}
      )

      :timer.sleep(50)

      assert has_element?(view, "#unshare-entry-#{entry.id}")
    end

    test "broadcast :shared_entry_removed refreshes the stream", %{
      conn: conn,
      scope_a: scope_a,
      link: link
    } do
      entry = create_shared_entry(scope_a, link.id)
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")

      assert has_element?(view, "#unshare-entry-#{entry.id}")

      {:ok, removed_entry} = SharedFinance.unshare_finance_entry(scope_a, entry.id)

      Phoenix.PubSub.broadcast(
        Organizer.PubSub,
        "account_link:#{link.id}",
        {:shared_entry_removed, removed_entry}
      )

      :timer.sleep(50)

      refute has_element?(view, "#unshare-entry-#{entry.id}")
    end
  end

  describe "imbalance indicator" do
    test "imbalance indicator is hidden when totals are zero", %{conn: conn} do
      %{user_a: user_a, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)

      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")

      refute has_element?(view, "#imbalance-indicator")
    end
  end

  describe "visual formatting" do
    setup %{conn: conn} do
      %{user_a: user_a, scope_a: scope_a, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)
      %{conn: conn, scope_a: scope_a, link: link}
    end

    test "renders money and percentages in pt-BR format", %{
      conn: conn,
      scope_a: scope_a,
      link: link
    } do
      _entry = create_shared_entry(scope_a, link.id)
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")
      html = render(view)

      assert html =~ "R$ 100,00"
      assert html =~ ~r/\d+,\d%/
      refute html =~ "R$ 100.00"
      refute html =~ "100.0%"
    end
  end
end
