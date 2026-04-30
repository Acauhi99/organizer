defmodule OrganizerWeb.DashboardLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.Planning

  defp create_expense_entry(scope, attrs) do
    {:ok, entry} = Planning.create_finance_entry(scope, attrs)
    entry
  end

  describe "finances list pagination" do
    test "resets to first page after deleting an entry", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      conn = log_in_user(conn, user)

      entries =
        Enum.map(0..20, fn offset ->
          create_expense_entry(scope, %{
            "description" => "Despesa #{offset}",
            "amount_cents" => 10_000 + offset,
            "kind" => "expense",
            "category" => "Categoria",
            "occurred_on" => Date.to_iso8601(Date.add(Date.utc_today(), -offset))
          })
        end)

      latest_entry = hd(entries)
      oldest_entry = List.last(entries)

      {:ok, view, _html} = live(conn, ~p"/finances")

      render_hook(view, "load_more_finances", %{"page" => 2})
      render_hook(view, "load_more_finances", %{"page" => 3})

      assert has_element?(view, "#finance-delete-btn-#{oldest_entry.id}")

      view
      |> element("#finance-delete-btn-#{oldest_entry.id}")
      |> render_click()

      view
      |> element("#finance-delete-confirm-btn")
      |> render_click()

      assert has_element?(view, "#finance-delete-btn-#{latest_entry.id}")
      refute has_element?(view, "#finance-delete-btn-#{oldest_entry.id}")
    end
  end
end
