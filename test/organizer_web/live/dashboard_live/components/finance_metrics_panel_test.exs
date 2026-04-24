defmodule OrganizerWeb.DashboardLive.Components.FinanceMetricsPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.FinanceMetricsPanel

  defp base_assigns do
    %{
      finance_metrics_filters: %{days: "30"},
      finance_highlights: %{
        finance_entries_window: 0,
        expense_entries_window: 0,
        income_cents: 0,
        expense_cents: 0,
        net_cents: 0,
        avg_expense_ticket_cents: 0,
        dominant_expense_category: nil,
        dominant_expense_share: 0.0,
        expense_composition_top: []
      },
      finance_flow_chart: %{loading: false, chart_svg: nil},
      finance_category_chart: %{loading: false, chart_svg: nil},
      finance_composition_chart: %{loading: false, chart_svg: nil}
    }
  end

  test "is deterministic for same assigns" do
    html1 = render_component(&FinanceMetricsPanel.finance_metrics_panel/1, base_assigns())
    html2 = render_component(&FinanceMetricsPanel.finance_metrics_panel/1, base_assigns())
    assert html1 == html2
  end

  test "renders expected ids and active chip" do
    html = render_component(&FinanceMetricsPanel.finance_metrics_panel/1, base_assigns())
    assert html =~ ~s(id="finance-metrics-panel")
    assert html =~ ~s(id="finance-metrics-days-30")
    assert html =~ ~r/id="finance-metrics-days-30"[^>]*btn-primary/
    assert html =~ ~s(id="chart-finance-flow")
    assert html =~ ~s(id="chart-finance-composition")
    assert html =~ ~s(id="chart-finance-category")
  end

  test "renders empty-state copy for charts when no data" do
    html = render_component(&FinanceMetricsPanel.finance_metrics_panel/1, base_assigns())
    assert html =~ "Sem lançamentos financeiros no período para montar o fluxo."
    assert html =~ "Sem despesas no período para montar composição."
    assert html =~ "Cadastre despesas para identificar categorias com maior impacto."
  end
end
