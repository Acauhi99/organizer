defmodule OrganizerWeb.DashboardLive.Components.DashboardHeaderTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.DashboardHeader

  # Feature: dashboard-components, Property 1: DashboardHeader é uma função pura
  # Validates: Requirements 1.1, 1.4
  property "DashboardHeader is a pure function - same assigns produce identical output" do
    check all(
            completed <- StreamData.integer(0..1000),
            total <- StreamData.integer(1..1000),
            income_cents <- StreamData.integer(),
            expense_cents <- StreamData.integer(),
            balance_cents <- StreamData.integer()
          ) do
      assigns = %{
        workload_capacity_snapshot: %{completed: completed, total: total},
        finance_summary: %{
          income_cents: income_cents,
          expense_cents: expense_cents,
          balance_cents: balance_cents
        }
      }

      html1 = render_component(&DashboardHeader.dashboard_header/1, assigns)
      html2 = render_component(&DashboardHeader.dashboard_header/1, assigns)

      assert html1 == html2
    end
  end

  describe "unit tests" do
    @valid_assigns %{
      workload_capacity_snapshot: %{completed: 5, total: 10},
      finance_summary: %{income_cents: 100_000, expense_cents: 60_000, balance_cents: 40_000}
    }

    test "renders with minimum valid assigns" do
      html = render_component(&DashboardHeader.dashboard_header/1, @valid_assigns)

      assert html =~ "Painel Diário"
      assert html =~ "Burndown"
      assert html =~ "Receitas"
      assert html =~ "Despesas"
      assert html =~ "Saldo"
    end

    test "shows positive balance classes" do
      assigns = put_in(@valid_assigns, [:finance_summary, :balance_cents], 5000)
      html = render_component(&DashboardHeader.dashboard_header/1, assigns)

      assert html =~ "text-emerald-300"
      assert html =~ "bg-emerald-500/12"
      assert html =~ "positivo"
    end

    test "shows negative balance classes" do
      assigns = put_in(@valid_assigns, [:finance_summary, :balance_cents], -5000)
      html = render_component(&DashboardHeader.dashboard_header/1, assigns)

      assert html =~ "text-rose-300"
      assert html =~ "bg-rose-500/12"
      assert html =~ "negativo"
    end

    test "shows zero balance classes" do
      assigns = put_in(@valid_assigns, [:finance_summary, :balance_cents], 0)
      html = render_component(&DashboardHeader.dashboard_header/1, assigns)

      assert html =~ "text-cyan-300"
      assert html =~ "bg-cyan-500/12"
      assert html =~ "neutro"
    end
  end
end
