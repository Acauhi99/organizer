defmodule OrganizerWeb.DashboardLive.Insights do
  @moduledoc """
  Analytics and chart SVG generation for DashboardLive.

  Encapsulates `refresh_dashboard_insights/1` and chart SVG builders.
  All functions are pure or delegate to `Organizer.Planning` and `Organizer.Planning.AnalyticsCache`.
  """

  alias Organizer.Planning
  alias Organizer.Planning.AnalyticsCache
  alias Contex.{Dataset, Plot}

  @spec refresh_dashboard_insights(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_dashboard_insights(socket) do
    analytics_result =
      AnalyticsCache.get_analytics(
        socket.assigns.current_scope,
        days: socket.assigns.analytics_filters.days,
        planned_capacity: socket.assigns.analytics_filters.planned_capacity
      )

    {:ok, workload_capacity_snapshot} =
      Planning.burndown_snapshot(socket.assigns.current_scope, %{
        planned_capacity: socket.assigns.analytics_filters.planned_capacity
      })

    {:ok, finance_summary} = Planning.finance_summary(socket.assigns.current_scope, 30)

    insights_overview =
      case analytics_result do
        {:ok, cached_analytics} ->
          cached_analytics

        {:error, _reason} ->
          %{
            progress_by_period: %{},
            workload_capacity: %{
              capacity_gap: 0,
              open_14d: 0,
              planned_capacity_14d: 10,
              overload_alert: false,
              overdue_open: 0,
              executed_last_7d: 0
            },
            burnout_risk_assessment: %{
              level: :low,
              score: 0,
              signals: []
            }
          }
      end

    socket
    |> Phoenix.Component.assign(:workload_capacity_snapshot, workload_capacity_snapshot)
    |> Phoenix.Component.assign(:insights_overview, insights_overview)
    |> Phoenix.Component.assign(:finance_summary, finance_summary)
  end

  @spec load_chart_svgs(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_chart_svgs(socket) do
    {:ok, finance_entries_for_charts} =
      Planning.list_finance_entries(socket.assigns.current_scope, %{
        days: socket.assigns.finance_filters.days
      })

    insights_overview = socket.assigns.insights_overview

    socket
    |> Phoenix.Component.assign(:progress_chart, %{
      loading: false,
      chart_svg: progress_chart_svg(insights_overview)
    })
    |> Phoenix.Component.assign(:finance_trend_chart, %{
      loading: false,
      chart_svg: finance_weekly_balance_chart_svg(finance_entries_for_charts)
    })
    |> Phoenix.Component.assign(:finance_category_chart, %{
      loading: false,
      chart_svg: finance_expense_categories_chart_svg(finance_entries_for_charts)
    })
  end

  @spec progress_chart_svg(map()) :: Phoenix.HTML.safe() | nil
  def progress_chart_svg(insights_overview) do
    progress = insights_overview.progress_by_period

    data = [
      {"Semanal", progress.weekly.executed, progress.weekly.planned},
      {"Mensal", progress.monthly.executed, progress.monthly.planned},
      {"Anual", progress.annual.executed, progress.annual.planned}
    ]

    dataset = Dataset.new(data, ["periodo", "executado", "planejado"])

    Plot.new(dataset, Contex.BarChart, 640, 260,
      mapping: %{category_col: "periodo", value_cols: ["executado", "planejado"]},
      type: :grouped,
      data_labels: false,
      title: "Progresso"
    )
    |> Plot.plot_options(%{legend_setting: :legend_bottom})
    |> Plot.to_svg()
  end

  @spec finance_weekly_balance_chart_svg(list()) :: Phoenix.HTML.safe() | nil
  def finance_weekly_balance_chart_svg(finance_entries) when is_list(finance_entries) do
    week_starts = rolling_week_starts(8)

    week_label_lookup =
      week_starts
      |> Enum.with_index(1)
      |> Map.new(fn {week_start, index} -> {index, short_date_label(week_start)} end)

    data =
      Enum.with_index(week_starts, 1)
      |> Enum.map(fn {week_start, index} ->
        week_end = Date.add(week_start, 6)

        net_cents =
          finance_entries
          |> Enum.filter(fn entry ->
            Date.compare(entry.occurred_on, week_start) in [:gt, :eq] and
              Date.compare(entry.occurred_on, week_end) in [:lt, :eq]
          end)
          |> Enum.reduce(0, fn entry, acc ->
            if entry.kind == :income,
              do: acc + entry.amount_cents,
              else: acc - entry.amount_cents
          end)

        {index, net_cents}
      end)

    dataset = Dataset.new(data, ["week_index", "saldo"])

    Plot.new(dataset, Contex.LinePlot, 520, 260,
      mapping: %{x_col: "week_index", y_cols: ["saldo"]},
      smoothed: false,
      custom_x_formatter: fn value ->
        week_label_for_axis(value, week_label_lookup)
      end,
      custom_y_formatter: &money_axis_formatter/1,
      title: "Saldo líquido por semana"
    )
    |> Plot.to_svg()
  end

  def finance_weekly_balance_chart_svg(_), do: finance_weekly_balance_chart_svg([])

  @spec finance_expense_categories_chart_svg(list()) :: Phoenix.HTML.safe() | nil
  def finance_expense_categories_chart_svg(finance_entries) when is_list(finance_entries) do
    data =
      finance_entries
      |> Enum.filter(&(&1.kind == :expense))
      |> Enum.group_by(&normalize_finance_category(&1.category))
      |> Enum.map(fn {category, entries} ->
        {category, Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount_cents end)}
      end)
      |> Enum.sort_by(fn {_category, total} -> -total end)
      |> Enum.take(5)

    data =
      if data == [] do
        [{"Sem despesas", 0}]
      else
        data
      end

    dataset = Dataset.new(data, ["categoria", "valor"])

    Plot.new(dataset, Contex.BarChart, 520, 260,
      mapping: %{category_col: "categoria", value_cols: ["valor"]},
      orientation: :horizontal,
      data_labels: false,
      title: "Top despesas por categoria",
      custom_value_formatter: &money_axis_formatter/1
    )
    |> Plot.to_svg()
  end

  def finance_expense_categories_chart_svg(_), do: finance_expense_categories_chart_svg([])

  defp rolling_week_starts(weeks) when is_integer(weeks) and weeks > 0 do
    today = Date.utc_today()
    week_start = Date.add(today, 1 - Date.day_of_week(today))
    oldest_start = Date.add(week_start, -7 * (weeks - 1))

    Enum.map(0..(weeks - 1), fn index ->
      Date.add(oldest_start, index * 7)
    end)
  end

  defp short_date_label(%Date{} = date) do
    day = date.day |> Integer.to_string() |> String.pad_leading(2, "0")
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{day}/#{month}"
  end

  defp week_label_for_axis(value, lookup) when is_number(value) and is_map(lookup) do
    rounded = round(value)

    if abs(value - rounded) < 0.001 do
      Map.get(lookup, rounded, "")
    else
      ""
    end
  end

  defp week_label_for_axis(_value, _lookup), do: ""

  defp normalize_finance_category(nil), do: "Sem categoria"

  defp normalize_finance_category(category) when is_binary(category) do
    category = String.trim(category)
    if category == "", do: "Sem categoria", else: category
  end

  defp normalize_finance_category(category), do: to_string(category)

  defp money_axis_formatter(value) when is_number(value) do
    "R$ " <> :erlang.float_to_binary(value / 100, decimals: 0)
  end
end
