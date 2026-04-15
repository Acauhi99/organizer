defmodule Organizer.Planning.AnalyticsTest do
  use ExUnit.Case, async: true

  alias Organizer.Planning.Analytics

  describe "progress_by_period/2" do
    test "computes weekly monthly and annual metrics" do
      today = ~D[2026-04-14]

      tasks = [
        task(%{status: :done, due_on: ~D[2026-04-12], completed_on: ~D[2026-04-13]}),
        task(%{status: :todo, due_on: ~D[2026-04-13]}),
        task(%{status: :done, due_on: ~D[2026-03-20], completed_on: ~D[2026-04-02]}),
        task(%{status: :todo, due_on: ~D[2026-01-10]}),
        task(%{status: :done, due_on: ~D[2025-09-10], completed_on: ~D[2025-10-01]})
      ]

      metrics = Analytics.progress_by_period(tasks, today)

      assert metrics.weekly.planned == 2
      assert metrics.weekly.executed == 1
      assert metrics.weekly.open == 1
      assert metrics.monthly.planned == 3
      assert metrics.annual.planned == 5
    end
  end

  describe "workload_capacity_snapshot/3" do
    test "flags overload when open workload exceeds planned capacity" do
      today = ~D[2026-04-14]

      tasks =
        Enum.map(1..8, fn idx ->
          task(%{status: :todo, due_on: Date.add(today, idx)})
        end) ++ [task(%{status: :done, due_on: ~D[2026-04-13], completed_on: ~D[2026-04-14]})]

      burndown = Analytics.workload_capacity_snapshot(tasks, 5, today)

      assert burndown.open_14d == 8
      assert burndown.executed_last_7d == 1
      assert burndown.capacity_gap == 3
      assert burndown.overload_alert
    end

    test "normalizes negative capacity and keeps alert off when workload fits" do
      today = ~D[2026-04-14]

      tasks = [
        task(%{status: :todo, due_on: Date.add(today, 1)}),
        task(%{status: :done, due_on: Date.add(today, -1), completed_on: today})
      ]

      burndown_zero = Analytics.workload_capacity_snapshot(tasks, -4, today)
      assert burndown_zero.planned_capacity_14d == 0
      assert burndown_zero.capacity_gap == 1

      burndown_ok = Analytics.workload_capacity_snapshot(tasks, 3, today)
      refute burndown_ok.overload_alert
      assert burndown_ok.capacity_gap == 0
    end
  end

  describe "burnout_risk_assessment/2" do
    test "returns high risk when backlog is late and delivery trend drops" do
      today = ~D[2026-04-14]

      overdue_open =
        Enum.map(1..10, fn idx ->
          task(%{status: :todo, due_on: Date.add(today, -idx)})
        end)

      previous_done =
        Enum.map(1..6, fn idx ->
          task(%{
            status: :done,
            due_on: Date.add(today, -idx - 20),
            completed_on: Date.add(today, -idx - 15)
          })
        end)

      recent_done = [
        task(%{status: :done, due_on: Date.add(today, -2), completed_on: Date.add(today, -1)})
      ]

      risk =
        Analytics.burnout_risk_assessment(overdue_open ++ previous_done ++ recent_done, today)

      assert risk.level == :high
      assert risk.score >= 70
      assert "atraso elevado" in risk.signals
    end

    test "returns low risk when backlog and completion are balanced" do
      today = ~D[2026-04-14]

      tasks = [
        task(%{status: :todo, due_on: Date.add(today, 2)}),
        task(%{status: :todo, due_on: Date.add(today, 4)}),
        task(%{status: :done, due_on: Date.add(today, -1), completed_on: Date.add(today, -1)}),
        task(%{status: :done, due_on: Date.add(today, -3), completed_on: Date.add(today, -2)}),
        task(%{status: :done, due_on: Date.add(today, -18), completed_on: Date.add(today, -17)})
      ]

      risk = Analytics.burnout_risk_assessment(tasks, today)

      assert risk.level == :low
      assert risk.score < 40
    end
  end

  defp task(attrs) do
    completed_at =
      case Map.get(attrs, :completed_on) do
        %Date{} = date -> DateTime.new!(date, ~T[09:00:00], "Etc/UTC")
        _ -> nil
      end

    %{
      status: Map.get(attrs, :status, :todo),
      due_on: Map.get(attrs, :due_on),
      completed_at: completed_at,
      updated_at: completed_at
    }
  end
end
