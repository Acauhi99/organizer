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
      finance_edit_modal_entry: nil,
      pending_finance_delete: nil,
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
    assert html =~ ~s(phx-hook="FinanceFormEnhancements")
    assert html =~ ~s(id="finance-filters")
    refute html =~ ~s(id="finance-filter-common-category")
    assert html =~ ~s(id="finance-filter-category")
    assert html =~ ~s(id="finances" phx-update="stream")
    assert html =~ ~s(id="finances-scroll-area")
    assert html =~ ~s(phx-hook="InfiniteScroll")
    assert html =~ ~s(data-money-mask="true")
    assert html =~ ~s(data-date-picker="date")
    assert html =~ "Exibindo 0 de 0 lançamentos"
  end

  test "renders finance empty state" do
    html = render_component(&FinanceOperationsPanel.finance_operations_panel/1, base_assigns())
    assert html =~ ~s(id="empty-state-finances")
  end

  test "renders fixed guidance and installment progress badge" do
    entry = %{
      id: 99,
      kind: :expense,
      expense_profile: :fixed,
      payment_method: :credit,
      installment_number: 6,
      installments_count: 10,
      amount_cents: 33_000,
      category: "Serviços compartilhados",
      description: "Internet e utilidades",
      occurred_on: Date.utc_today()
    }

    html =
      render_component(
        &FinanceOperationsPanel.finance_operations_panel/1,
        base_assigns()
        |> Map.put(:streams, %{finances: [{"finances-99", entry}]})
        |> Map.put(:ops_counts, %{base_assigns().ops_counts | finances_total: 1})
        |> Map.put(:finance_visible_count, 1)
      )

    assert html =~ ~s(id="finance-fixed-guidance")
    assert html =~ "Parcela 6/10"
    assert html =~ "Ativa até cancelar"
  end

  test "formats amount input with decimal places while editing" do
    entry = %{
      id: 101,
      kind: :expense,
      expense_profile: :variable,
      payment_method: :credit,
      installment_number: 1,
      installments_count: 2,
      amount_cents: 33_000,
      category: "Serviços compartilhados",
      description: "Internet e utilidades",
      occurred_on: Date.utc_today()
    }

    html =
      render_component(
        &FinanceOperationsPanel.finance_operations_panel/1,
        base_assigns()
        |> Map.put(:streams, %{finances: [{"finances-101", entry}]})
        |> Map.put(:editing_finance_id, 101)
        |> Map.put(:finance_edit_modal_entry, entry)
      )

    assert html =~ ~s(id="finance-edit-modal")
    assert html =~ ~s(name="finance[amount_cents]")
    assert html =~ ~s(value="330,00")
    assert html =~ ~s(data-money-mask="true")
    refute html =~ ~s(id="finance-common-category-101")
    refute html =~ ~s(data-category-shortcut-for="finance-category-101")
    assert html =~ ~s(name="finance[installment_number]")
  end

  test "renders deletion confirmation modal when an entry is pending deletion" do
    html =
      render_component(
        &FinanceOperationsPanel.finance_operations_panel/1,
        base_assigns()
        |> Map.put(:pending_finance_delete, %{id: 7, category: "Moradia"})
      )

    assert html =~ ~s(id="finance-delete-confirmation-modal")
    assert html =~ ~s(id="finance-delete-confirm-btn")
    assert html =~ "Moradia"
  end
end
