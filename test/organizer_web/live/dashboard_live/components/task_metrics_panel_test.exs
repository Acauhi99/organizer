defmodule OrganizerWeb.DashboardLive.Components.TaskMetricsPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.TaskMetricsPanel

  defp base_assigns do
    %{
      task_metrics_filters: %{days: "30", planned_capacity: "10"},
      insights_overview: %{burnout_risk_assessment: %{level: :low, score: 0, signals: []}},
      workload_capacity_snapshot: %{
        open_14d: 0,
        planned_capacity_14d: 10,
        capacity_gap: 0,
        overload_alert: false
      },
      task_delivery_chart: %{loading: false, chart_svg: nil},
      task_priority_chart: %{loading: false, chart_svg: nil},
      task_highlights: %{
        tasks_created_window: 0,
        tasks_completed_window: 0,
        tasks_total_window: 0,
        tasks_completion_rate: 0.0,
        open_high_priority: 0,
        overdue_open: 0
      }
    }
  end

  test "is deterministic for same assigns" do
    html1 = render_component(&TaskMetricsPanel.task_metrics_panel/1, base_assigns())
    html2 = render_component(&TaskMetricsPanel.task_metrics_panel/1, base_assigns())
    assert html1 == html2
  end

  test "renders expected ids and active chips" do
    html = render_component(&TaskMetricsPanel.task_metrics_panel/1, base_assigns())
    assert html =~ ~s(id="task-metrics-panel")
    assert html =~ ~s(id="task-metrics-days-30")
    assert html =~ ~s(id="task-metrics-capacity-10")
    assert html =~ ~r/id="task-metrics-days-30"[^>]*btn-primary/
    assert html =~ ~r/id="task-metrics-capacity-10"[^>]*btn-primary/
  end

  test "renders empty-state copy for charts when no data" do
    html = render_component(&TaskMetricsPanel.task_metrics_panel/1, base_assigns())
    assert html =~ "Sem atividade de tarefas no período selecionado."
    assert html =~ "Sem tarefas relevantes no período para comparar prioridades."
  end
end
