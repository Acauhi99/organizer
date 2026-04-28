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

  defp create_shared_expense_entry(scope, link_id, attrs \\ %{}) do
    defaults = %{
      "description" => "Despesa compartilhada",
      "amount_cents" => 10_000,
      "kind" => "expense",
      "category" => "Moradia",
      "occurred_on" => Date.to_iso8601(Date.utc_today())
    }

    {:ok, entry} =
      Planning.create_finance_entry(scope, Map.merge(defaults, attrs))

    {:ok, updated_entry} = SharedFinance.share_finance_entry(scope, entry.id, link_id)
    updated_entry
  end

  defp create_shared_entry_on(scope, link_id, date, amount_cents) do
    {:ok, entry} =
      Planning.create_finance_entry(scope, %{
        "description" => "Shared expense #{Date.to_iso8601(date)}",
        "amount_cents" => amount_cents,
        "kind" => "expense",
        "category" => "Moradia",
        "occurred_on" => Date.to_iso8601(date)
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
      %{user_a: user_a, scope_a: scope_a, scope_b: scope_b, link: link} = setup_linked_users()
      conn = log_in_user(conn, user_a)
      %{conn: conn, scope_a: scope_a, scope_b: scope_b, link: link}
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

    test "renders shared finance charts", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")
      assert has_element?(view, "#shared-balance-chart")
      assert has_element?(view, "#shared-trend-chart")
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

    test "requires confirmation before unsharing a shared entry", %{
      conn: conn,
      scope_a: scope_a,
      link: link
    } do
      entry = create_shared_entry(scope_a, link.id)
      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")

      assert has_element?(view, "#unshare-entry-#{entry.id}")

      view
      |> element("#unshare-entry-#{entry.id}")
      |> render_click()

      assert has_element?(view, "#shared-entry-unshare-confirmation-modal")
      assert has_element?(view, "#confirm-unshare-entry-btn")
      assert has_element?(view, "#unshare-entry-#{entry.id}")

      view
      |> element("#confirm-unshare-entry-btn")
      |> render_click()

      refute has_element?(view, "#unshare-entry-#{entry.id}")
    end

    test "renders edit button only for entries created by current user", %{
      conn: conn,
      scope_a: scope_a,
      scope_b: scope_b,
      link: link
    } do
      my_entry = create_shared_expense_entry(scope_a, link.id)
      other_entry = create_shared_expense_entry(scope_b, link.id)

      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")

      assert has_element?(view, "#edit-shared-entry-#{my_entry.id}")
      refute has_element?(view, "#edit-shared-entry-#{other_entry.id}")
    end

    test "opens modal and updates shared entry using percentage split", %{
      conn: conn,
      scope_a: scope_a,
      link: link
    } do
      entry =
        create_shared_expense_entry(scope_a, link.id, %{
          "description" => "Mercado antigo",
          "amount_cents" => 20_000
        })

      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")

      view
      |> element("#edit-shared-entry-#{entry.id}")
      |> render_click()

      assert has_element?(view, "#shared-entry-edit-modal")
      assert has_element?(view, "#shared-entry-edit-form")

      view
      |> form("#shared-entry-edit-form", %{
        "shared_entry_edit" => %{
          "split_type" => "percentage"
        }
      })
      |> render_change()

      today = Date.utc_today() |> Organizer.DateSupport.format_pt_br()

      view
      |> form("#shared-entry-edit-form", %{
        "shared_entry_edit" => %{
          "description" => "Mercado ajustado",
          "category" => "Alimentação",
          "amount_cents" => "300,00",
          "occurred_on" => today,
          "split_type" => "percentage",
          "split_mine_percentage" => "30,0",
          "split_mine_amount" => "90,00"
        }
      })
      |> render_submit()

      refute has_element?(view, "#shared-entry-edit-modal")

      assert {:ok, updated} = Planning.get_finance_entry(scope_a, entry.id)
      assert updated.amount_cents == 30_000
      assert updated.category == "Alimentação"
      assert updated.description == "Mercado ajustado"
      assert updated.shared_split_mode == :manual
      assert updated.shared_manual_mine_cents == 9_000
    end

    test "filters shared entries by selected period", %{conn: conn, scope_a: scope_a, link: link} do
      current_date = Date.utc_today()
      old_date = Date.add(current_date, -150)

      current_entry = create_shared_entry_on(scope_a, link.id, current_date, 12_000)
      old_entry = create_shared_entry_on(scope_a, link.id, old_date, 7_000)

      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}")

      assert has_element?(view, "#unshare-entry-#{current_entry.id}")
      assert has_element?(view, "#unshare-entry-#{old_entry.id}")
      assert has_element?(view, "#shared-period-filter-all.btn-primary")

      view
      |> element("#shared-period-filter-current-month")
      |> render_click()

      patched_path = assert_patch(view)
      assert String.starts_with?(patched_path, ~p"/account-links/#{link.id}")

      params =
        patched_path
        |> URI.parse()
        |> Map.get(:query, "")
        |> Plug.Conn.Query.decode()

      assert params == %{"period" => "current_month"}

      assert has_element?(view, "#shared-period-filter-current-month.btn-primary")
      assert has_element?(view, "#unshare-entry-#{current_entry.id}")
      refute has_element?(view, "#unshare-entry-#{old_entry.id}")
    end

    test "reads selected period from query params", %{conn: conn, scope_a: scope_a, link: link} do
      current_date = Date.utc_today()
      old_date = Date.add(current_date, -120)

      current_entry = create_shared_entry_on(scope_a, link.id, current_date, 12_000)
      old_entry = create_shared_entry_on(scope_a, link.id, old_date, 7_000)

      {:ok, view, _html} = live(conn, ~p"/account-links/#{link.id}?period=current_month")

      assert has_element?(view, "#shared-period-filter-current-month.btn-primary")
      assert has_element?(view, "#unshare-entry-#{current_entry.id}")
      refute has_element?(view, "#unshare-entry-#{old_entry.id}")
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
