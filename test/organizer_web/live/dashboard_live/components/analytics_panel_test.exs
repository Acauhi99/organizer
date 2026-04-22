defmodule OrganizerWeb.DashboardLive.Components.AnalyticsPanelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.AnalyticsPanel

  # Feature: dashboard-components, Property 3: AnalyticsPanel é uma função pura
  # Validates: Requirements 3.1, 3.4
  property "AnalyticsPanel is a pure function - same assigns produce identical output" do
    check all(
            days <- StreamData.member_of(["7", "15", "30", "90", "365"]),
            planned_capacity <- StreamData.member_of(["5", "10", "15", "20", "30"]),
            weekly_executed <- StreamData.integer(0..100),
            weekly_planned <- StreamData.integer(0..100),
            weekly_rate <- StreamData.integer(0..100),
            monthly_executed <- StreamData.integer(0..100),
            monthly_planned <- StreamData.integer(0..100),
            monthly_rate <- StreamData.integer(0..100),
            annual_executed <- StreamData.integer(0..100),
            annual_planned <- StreamData.integer(0..100),
            annual_rate <- StreamData.integer(0..100),
            burnout_level <- StreamData.member_of([:low, :medium, :high]),
            burnout_score <- StreamData.integer(0..100),
            open_14d <- StreamData.integer(0..100),
            planned_capacity_14d <- StreamData.integer(0..100),
            capacity_gap <- StreamData.integer(-50..50),
            overload_alert <- StreamData.boolean(),
            tasks_created_window <- StreamData.integer(0..100),
            tasks_completed_window <- StreamData.integer(0..100),
            open_high_priority <- StreamData.integer(0..40),
            overdue_open <- StreamData.integer(0..40),
            finances_total <- StreamData.integer(0..100)
          ) do
      assigns = %{
        analytics_filters: %{
          days: days,
          planned_capacity: planned_capacity
        },
        insights_overview: %{
          progress_by_period: %{
            weekly: %{
              executed: weekly_executed,
              planned: weekly_planned,
              completion_rate: weekly_rate / 100.0
            },
            monthly: %{
              executed: monthly_executed,
              planned: monthly_planned,
              completion_rate: monthly_rate / 100.0
            },
            annual: %{
              executed: annual_executed,
              planned: annual_planned,
              completion_rate: annual_rate / 100.0
            }
          },
          burnout_risk_assessment: %{
            level: burnout_level,
            score: burnout_score,
            signals: []
          }
        },
        workload_capacity_snapshot: %{
          open_14d: open_14d,
          planned_capacity_14d: planned_capacity_14d,
          capacity_gap: capacity_gap,
          overload_alert: overload_alert
        },
        progress_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        finance_trend_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        finance_category_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        task_priority_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        finance_mix_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        analytics_highlights: %{
          tasks_created_window: tasks_created_window,
          tasks_completed_window: tasks_completed_window,
          tasks_total_window: tasks_created_window + tasks_completed_window,
          tasks_completion_rate: 0.0,
          open_high_priority: open_high_priority,
          overdue_open: overdue_open,
          finance_entries_window: finances_total,
          expense_entries_window: max(finances_total - 5, 0),
          income_cents: 10_000,
          expense_cents: 8_000,
          net_cents: 2_000,
          avg_expense_ticket_cents: 1_000,
          dominant_expense_category: "Moradia",
          dominant_expense_share: 38.4,
          expense_mix_top: [
            %{label: "Moradia", share: 38.4, amount_cents: 3_840},
            %{label: "Alimentação", share: 24.8, amount_cents: 2_480}
          ]
        },
        ops_counts: %{finances_total: finances_total}
      }

      html1 = render_component(&AnalyticsPanel.analytics_panel/1, assigns)
      html2 = render_component(&AnalyticsPanel.analytics_panel/1, assigns)

      assert html1 == html2
    end
  end

  # Unit tests for AnalyticsPanel
  # Validates: Requirements 3.1, 3.3
  describe "unit tests" do
    defp base_assigns do
      %{
        analytics_filters: %{days: "30", planned_capacity: "10"},
        insights_overview: %{
          progress_by_period: %{
            weekly: %{executed: 0, planned: 0, completion_rate: 0.0},
            monthly: %{executed: 0, planned: 0, completion_rate: 0.0},
            annual: %{executed: 0, planned: 0, completion_rate: 0.0}
          },
          burnout_risk_assessment: %{
            level: :low,
            score: 0,
            signals: []
          }
        },
        workload_capacity_snapshot: %{
          open_14d: 0,
          planned_capacity_14d: 10,
          capacity_gap: 0,
          overload_alert: false
        },
        progress_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        finance_trend_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        finance_category_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        task_priority_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        finance_mix_chart: %{loading: false, chart_svg: Phoenix.HTML.raw("")},
        analytics_highlights: %{
          tasks_created_window: 0,
          tasks_completed_window: 0,
          tasks_total_window: 0,
          tasks_completion_rate: 0.0,
          open_high_priority: 0,
          overdue_open: 0,
          finance_entries_window: 0,
          expense_entries_window: 0,
          income_cents: 0,
          expense_cents: 0,
          net_cents: 0,
          avg_expense_ticket_cents: 0,
          dominant_expense_category: nil,
          dominant_expense_share: 0.0,
          expense_mix_top: []
        },
        ops_counts: %{finances_total: 0}
      }
    end

    test "shows no data message when progress chart has no data" do
      html = render_component(&AnalyticsPanel.analytics_panel/1, base_assigns())
      assert html =~ "Sem atividade de tarefas no período selecionado."
    end

    test "shows days filter chips" do
      html = render_component(&AnalyticsPanel.analytics_panel/1, base_assigns())
      assert html =~ ~s(id="analytics-days-7")
      assert html =~ ~s(id="analytics-days-30")
      assert html =~ ~s(id="analytics-days-90")
      assert html =~ ~s(id="analytics-days-365")
    end

    test "highlights active days filter chip" do
      assigns = put_in(base_assigns(), [:analytics_filters, :days], "30")
      html = render_component(&AnalyticsPanel.analytics_panel/1, assigns)

      assert html =~ ~r/id="analytics-days-30"[^>]*class="[^"]*btn-primary/
    end

    test "highlights active capacity filter chip" do
      assigns = put_in(base_assigns(), [:analytics_filters, :planned_capacity], "10")
      html = render_component(&AnalyticsPanel.analytics_panel/1, assigns)

      assert html =~ ~r/id="analytics-capacity-10"[^>]*class="[^"]*btn-primary/
    end
  end
end
