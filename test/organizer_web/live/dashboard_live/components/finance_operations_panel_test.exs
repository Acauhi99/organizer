defmodule OrganizerWeb.DashboardLive.Components.FinanceOperationsPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.FinanceOperationsPanel

  defp base_assigns do
    %{
      streams: %{finances: []},
      finance_filters: %{
        period_mode: "rolling",
        days: "30",
        month: "",
        occurred_on: "",
        occurred_from: "",
        occurred_to: "",
        weekday: "all",
        sort_by: "date_desc",
        kind: "all",
        expense_profile: "all",
        payment_method: "all",
        category: "",
        q: "",
        min_amount_cents: "",
        max_amount_cents: ""
      },
      category_suggestions: %{income: [], expense: [], all: []},
      editing_finance_id: nil,
      ops_counts: %{
        finances_total: 0,
        finances_income_total: 0,
        finances_expense_total: 0,
        finances_income_cents: 0,
        finances_expense_cents: 0
      }
    }
  end

  test "is deterministic for same assigns" do
    html1 = render_component(&FinanceOperationsPanel.finance_operations_panel/1, base_assigns())
    html2 = render_component(&FinanceOperationsPanel.finance_operations_panel/1, base_assigns())
    assert html1 == html2
  end

  test "renders panel and filters" do
    html = render_component(&FinanceOperationsPanel.finance_operations_panel/1, base_assigns())
    assert html =~ ~s(id="finance-operations-panel")
    assert html =~ ~s(id="finance-filters")
    assert html =~ ~s(id="finances" phx-update="stream")
  end

  test "renders finance empty state" do
    html = render_component(&FinanceOperationsPanel.finance_operations_panel/1, base_assigns())
    assert html =~ ~s(id="empty-state-finances")
  end
end
