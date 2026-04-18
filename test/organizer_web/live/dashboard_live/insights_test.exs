defmodule OrganizerWeb.DashboardLive.InsightsTest do
  use ExUnit.Case, async: true

  alias OrganizerWeb.DashboardLive.Insights

  # ---------------------------------------------------------------------------
  # progress_chart_svg/1 — smoke tests
  # ---------------------------------------------------------------------------

  describe "progress_chart_svg/1" do
    test "returns SVG for zero data" do
      insights = %{
        progress_by_period: %{
          weekly: %{executed: 0, planned: 0, completion_rate: 0.0},
          monthly: %{executed: 0, planned: 0, completion_rate: 0.0},
          annual: %{executed: 0, planned: 0, completion_rate: 0.0}
        }
      }

      result = Insights.progress_chart_svg(insights)
      assert {:safe, _} = result
    end

    test "returns SVG with data" do
      insights = %{
        progress_by_period: %{
          weekly: %{executed: 3, planned: 5, completion_rate: 0.6},
          monthly: %{executed: 10, planned: 20, completion_rate: 0.5},
          annual: %{executed: 50, planned: 100, completion_rate: 0.5}
        }
      }

      result = Insights.progress_chart_svg(insights)
      assert {:safe, _} = result
    end
  end
end
