defmodule Organizer.Planning.Analytics do
  @moduledoc """
  Pure analytics rules used by Planning for progress metrics,
  workload capacity snapshots and burnout risk signals.
  """

  @high_risk_score 70
  @medium_risk_score 40

  def progress_by_period(tasks, today \\ Date.utc_today()) when is_list(tasks) do
    %{
      weekly: period_progress_metrics(tasks, Date.add(today, -6), today, today),
      monthly: period_progress_metrics(tasks, Date.add(today, -29), today, today),
      annual: period_progress_metrics(tasks, Date.add(today, -364), today, today)
    }
  end

  def workload_capacity_snapshot(tasks, planned_capacity_14d \\ 10, today \\ Date.utc_today())
      when is_list(tasks) do
    capacity = max(planned_capacity_14d, 0)
    horizon_end = Date.add(today, 14)

    open_14d =
      Enum.count(tasks, fn task ->
        open_task?(task) and
          (is_nil(due_date(task)) or Date.compare(due_date(task), horizon_end) in [:lt, :eq])
      end)

    executed_last_7d =
      Enum.count(tasks, fn task ->
        done_task?(task) and
          case completed_on(task) do
            %Date{} = completed -> Date.compare(completed, Date.add(today, -6)) in [:gt, :eq]
            _ -> false
          end
      end)

    overdue_open =
      Enum.count(tasks, fn task ->
        open_task?(task) and not is_nil(due_date(task)) and
          Date.compare(due_date(task), today) == :lt
      end)

    %{
      planned_capacity_14d: capacity,
      open_14d: open_14d,
      executed_last_7d: executed_last_7d,
      overdue_open: overdue_open,
      capacity_gap: max(open_14d - capacity, 0),
      overload_alert: open_14d > capacity
    }
  end

  def burnout_risk_assessment(tasks, today \\ Date.utc_today()) when is_list(tasks) do
    open_tasks = Enum.count(tasks, &open_task?/1)

    overdue_open =
      Enum.count(tasks, fn task ->
        open_task?(task) and not is_nil(due_date(task)) and
          Date.compare(due_date(task), today) == :lt
      end)

    recent_completed = count_completed_between(tasks, Date.add(today, -13), today)

    previous_completed =
      count_completed_between(tasks, Date.add(today, -27), Date.add(today, -14))

    overdue_ratio = safe_ratio(overdue_open, max(open_tasks, 1))
    open_load_ratio = min(open_tasks / 20, 1.0)
    completion_trend_drop = trend_drop(previous_completed, recent_completed)

    score =
      round(
        (0.45 * overdue_ratio + 0.35 * open_load_ratio + 0.20 * completion_trend_drop) *
          100
      )

    %{
      score: score,
      level: risk_level(score),
      factors: %{
        overdue_ratio: round1(overdue_ratio * 100),
        open_load_ratio: round1(open_load_ratio * 100),
        completion_trend_drop: round1(completion_trend_drop * 100)
      },
      signals: signals(overdue_ratio, open_load_ratio, completion_trend_drop)
    }
  end

  defp period_progress_metrics(tasks, start_date, end_date, today) do
    planned =
      Enum.count(tasks, fn task ->
        case due_date(task) do
          %Date{} = due -> in_range?(due, start_date, end_date)
          _ -> false
        end
      end)

    executed =
      Enum.count(tasks, fn task ->
        done_task?(task) and
          case completed_on(task) do
            %Date{} = completed -> in_range?(completed, start_date, end_date)
            _ -> false
          end
      end)

    open =
      Enum.count(tasks, fn task ->
        open_task?(task) and
          case due_date(task) do
            %Date{} = due -> in_range?(due, start_date, end_date)
            _ -> false
          end
      end)

    overdue_open =
      Enum.count(tasks, fn task ->
        open_task?(task) and not is_nil(due_date(task)) and
          Date.compare(due_date(task), today) == :lt
      end)

    %{
      planned: planned,
      executed: executed,
      open: open,
      overdue_open: overdue_open,
      completion_rate: completion_rate(executed, planned)
    }
  end

  defp completion_rate(_executed, 0), do: 0.0
  defp completion_rate(executed, planned), do: round1(executed / planned * 100)

  defp count_completed_between(tasks, start_date, end_date) do
    Enum.count(tasks, fn task ->
      done_task?(task) and
        case completed_on(task) do
          %Date{} = completed -> in_range?(completed, start_date, end_date)
          _ -> false
        end
    end)
  end

  defp trend_drop(0, 0), do: 0.0
  defp trend_drop(0, _recent_completed), do: 0.0

  defp trend_drop(previous_completed, recent_completed) do
    ratio = (previous_completed - recent_completed) / previous_completed
    max(ratio, 0.0)
  end

  defp signals(overdue_ratio, open_load_ratio, completion_trend_drop) do
    []
    |> maybe_add_signal(overdue_ratio > 0.40, "atraso elevado")
    |> maybe_add_signal(open_load_ratio > 0.65, "carga aberta alta")
    |> maybe_add_signal(completion_trend_drop > 0.35, "tendencia de entrega em queda")
  end

  defp maybe_add_signal(signals, true, signal), do: [signal | signals]
  defp maybe_add_signal(signals, false, _signal), do: signals

  defp risk_level(score) when score >= @high_risk_score, do: :high
  defp risk_level(score) when score >= @medium_risk_score, do: :medium
  defp risk_level(_score), do: :low

  defp in_range?(date, start_date, end_date) do
    Date.compare(date, start_date) in [:gt, :eq] and Date.compare(date, end_date) in [:lt, :eq]
  end

  defp safe_ratio(_numerator, 0), do: 0.0
  defp safe_ratio(numerator, denominator), do: numerator / denominator

  defp round1(value), do: Float.round(value * 1.0, 1)

  defp done_task?(task), do: status(task) == :done
  defp open_task?(task), do: status(task) != :done

  defp completed_on(task) do
    with %DateTime{} = dt <- Map.get(task, :completed_at) || Map.get(task, :updated_at) do
      DateTime.to_date(dt)
    end
  end

  defp due_date(task), do: Map.get(task, :due_on)
  defp status(task), do: Map.get(task, :status)
end
