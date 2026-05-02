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

  test "renders panel with basic and advanced filters" do
    html = render_component(&FinanceOperationsPanel.finance_operations_panel/1, base_assigns())
    assert html =~ ~s(id="finance-operations-panel")
    assert html =~ ~s(phx-hook="FinanceFormEnhancements")
    assert html =~ ~s(id="finance-filters")
    assert html =~ ~s(id="finance-filters-basic")
    assert html =~ ~s(id="finance-filters-advanced")
    assert html =~ ~s(id="finance-filters-advanced-summary")
    assert html =~ ~s(id="finance-filters-advanced-guidance")
    assert html =~ ~s(id="finance-filter-period-mode")
    assert html =~ ~s(id="finance-filter-q")
    refute html =~ ~s(id="finance-filter-common-category")
    assert html =~ ~s(id="finance-filter-category")
    assert html =~ ~s(id="finances" phx-update="stream")
    assert html =~ ~s(id="finances-scroll-area")
    assert html =~ ~s(phx-hook="InfiniteScroll")
    assert html =~ ~s(data-event="load_more_finances")
    assert html =~ ~s(data-money-mask="true")
    refute html =~ ~s(id="finance-filter-occurred-on")
    refute html =~ ~s(id="finance-filter-month")
    refute html =~ ~s(id="finance-filter-occurred-from")
    refute html =~ ~s(id="finance-filter-occurred-to")
    refute html =~ ~s(id="finance-filter-weekday")
    assert html =~ "Exibindo 0 de 0 lançamentos"
  end

  test "keeps advanced filters collapsed for default quick filtering" do
    html = render_component(&FinanceOperationsPanel.finance_operations_panel/1, base_assigns())

    refute html =~
             ~s(id="finance-filters-advanced" class="rounded-xl border border-base-content/12 bg-base-100/24 p-3" open)
  end

  test "auto-expands advanced filters when advanced fields are active" do
    html =
      render_component(
        &FinanceOperationsPanel.finance_operations_panel/1,
        base_assigns()
        |> put_in([:finance_filters, :period_mode], "range")
      )

    assert html =~
             ~s(id="finance-filters-advanced" class="rounded-xl border border-base-content/12 bg-base-100/24 p-3" open)

    assert html =~ ~s(id="finance-filter-occurred-from")
    assert html =~ ~s(id="finance-filter-occurred-to")
    refute html =~ ~s(id="finance-filter-days")
  end

  test "shows specific date input and contextual summary when period mode is specific_date" do
    html =
      render_component(
        &FinanceOperationsPanel.finance_operations_panel/1,
        base_assigns()
        |> put_in([:finance_filters, :period_mode], "specific_date")
        |> put_in([:finance_filters, :occurred_on], "12/03/2026")
      )

    assert html =~ ~s(id="finance-filter-occurred-on")
    assert html =~ ~s(data-date-picker="date")
    assert html =~ "12/03/2026"
    refute html =~ ~s(id="finance-filter-days")
    assert html =~ "Saldo financeiro em data 12/03/2026"
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
