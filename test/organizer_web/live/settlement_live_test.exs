defmodule OrganizerWeb.SettlementLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.SharedFinance

  defp setup_linked_users do
    user_a = user_fixture()
    user_b = user_fixture()

    scope_a = user_scope_fixture(user_a)
    scope_b = user_scope_fixture(user_b)

    {:ok, invite} = SharedFinance.create_invite(scope_a)
    {:ok, link} = SharedFinance.accept_invite(scope_b, invite.token)

    %{user_a: user_a, user_b: user_b, scope_a: scope_a, scope_b: scope_b, link: link}
  end

  describe "access" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/account-links/1/settlement")
    end

    test "redirects to account-links when link not found", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/account-links"}}} =
               live(conn, ~p"/account-links/999999/settlement")
    end
  end

  describe "renders settlement balance and records list" do
    setup %{conn: conn} do
      %{user_a: user_a, scope_a: scope_a, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)
      %{conn: conn, scope_a: scope_a, link: link}
    end

    test "renders settlement balance section", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")
      assert has_element?(view, "#settlement-balance")
    end

    test "renders settlement records list", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")
      assert has_element?(view, "#settlement-records-list")
    end

    test "renders new record form", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")
      assert has_element?(view, "#new-record-form")
    end

    test "renders confirm settlement button", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")
      assert has_element?(view, "#confirm-settlement-btn")
    end

    test "renders settle button", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")
      assert has_element?(view, "#settle-btn")
    end
  end

  describe "settlement records in chronological order" do
    setup %{conn: conn} do
      %{user_a: user_a, scope_a: scope_a, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)

      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, Date.utc_today())

      %{conn: conn, scope_a: scope_a, link: link, cycle: cycle}
    end

    test "shows records in the stream after creation", %{
      conn: conn,
      scope_a: scope_a,
      link: link,
      cycle: cycle
    } do
      earlier = ~U[2024-01-01 00:00:00Z]
      later = ~U[2024-01-15 00:00:00Z]

      {:ok, record_later} =
        SharedFinance.create_settlement_record(scope_a, cycle.id, %{
          amount_cents: 3000,
          method: :pix,
          transferred_at: later
        })

      {:ok, record_earlier} =
        SharedFinance.create_settlement_record(scope_a, cycle.id, %{
          amount_cents: 2000,
          method: :pix,
          transferred_at: earlier
        })

      {:ok, view, html} = live(conn, ~p"/account-links/#{link.id}/settlement")

      assert has_element?(view, "#settlement-records-list")

      earlier_id = "settlement_records-#{record_earlier.id}"
      later_id = "settlement_records-#{record_later.id}"

      assert has_element?(view, "##{earlier_id}"),
             "Earlier record element not found. HTML: #{html}"

      assert has_element?(view, "##{later_id}"),
             "Later record element not found. HTML: #{html}"

      {earlier_start, _} = :binary.match(html, earlier_id)
      {later_start, _} = :binary.match(html, later_id)

      assert earlier_start < later_start,
             "Earlier record should appear before later record in the list"
    end
  end

  describe "confirm button" do
    setup %{conn: conn} do
      %{user_a: user_a, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)
      %{conn: conn, link: link}
    end

    test "confirm button is present and clickable", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")

      assert has_element?(view, "#confirm-settlement-btn")

      view |> element("#confirm-settlement-btn") |> render_click()

      html = render(view)
      assert html =~ "Confirmação registrada." or html =~ "Aguardando confirmação do parceiro."
    end
  end

  describe "settle button disabled without bilateral confirmation" do
    setup %{conn: conn} do
      %{user_a: user_a, scope_a: scope_a, scope_b: scope_b, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)
      %{conn: conn, scope_a: scope_a, scope_b: scope_b, link: link}
    end

    test "settle button is disabled when neither user has confirmed", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")
      assert has_element?(view, "#settle-btn[disabled]")
    end

    test "settle button is disabled when only one user has confirmed", %{
      conn: conn,
      scope_a: scope_a,
      link: link
    } do
      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, Date.utc_today())

      SharedFinance.confirm_settlement(scope_a, cycle.id)

      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")
      assert has_element?(view, "#settle-btn[disabled]")
    end

    test "settle button is enabled when both users have confirmed", %{
      conn: conn,
      scope_a: scope_a,
      scope_b: scope_b,
      link: link
    } do
      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, Date.utc_today())

      SharedFinance.confirm_settlement(scope_a, cycle.id)
      {:ok, _updated_cycle} = SharedFinance.confirm_settlement(scope_b, cycle.id)

      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}/settlement")
      refute has_element?(view, "#settle-btn[disabled]")
    end
  end
end
