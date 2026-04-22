defmodule OrganizerWeb.DashboardLive.Insights do
  @moduledoc """
  Analytics and chart SVG generation for DashboardLive.

  Encapsulates `refresh_dashboard_insights/1` and chart SVG builders.
  All functions are pure or delegate to `Organizer.Planning` and `Organizer.Planning.AnalyticsCache`.
  """

  alias Contex.{Dataset, Plot}
  alias Contex.PieChart
  alias Organizer.Planning
  alias Organizer.Planning.AnalyticsCache

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

  @spec default_analytics_highlights() :: map()
  def default_analytics_highlights do
    %{
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
    }
  end

  @spec load_chart_svgs(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_chart_svgs(socket) do
    analytics_days = parse_days(socket.assigns.analytics_filters.days, 30)
    start_on = Date.add(Date.utc_today(), -(analytics_days - 1))

    {:ok, tasks} =
      Planning.list_tasks(socket.assigns.current_scope, %{
        days: analytics_days,
        status: "all",
        priority: "all"
      })

    {:ok, finance_entries} =
      Planning.list_finance_entries(socket.assigns.current_scope, %{
        days: analytics_days,
        kind: "all",
        expense_profile: "all",
        payment_method: "all"
      })

    tasks_window =
      Enum.filter(tasks, fn task ->
        task_relevant_for_window?(task, start_on)
      end)

    analytics_highlights = build_analytics_highlights(tasks_window, finance_entries, start_on)

    socket
    |> Phoenix.Component.assign(:progress_chart, %{
      loading: false,
      chart_svg: task_delivery_chart_svg(tasks_window, analytics_days)
    })
    |> Phoenix.Component.assign(:finance_trend_chart, %{
      loading: false,
      chart_svg: finance_flow_chart_svg(finance_entries, analytics_days)
    })
    |> Phoenix.Component.assign(:finance_category_chart, %{
      loading: false,
      chart_svg: finance_expense_categories_chart_svg(finance_entries)
    })
    |> Phoenix.Component.assign(:task_priority_chart, %{
      loading: false,
      chart_svg: task_priority_comparison_chart_svg(tasks_window)
    })
    |> Phoenix.Component.assign(:finance_mix_chart, %{
      loading: false,
      chart_svg: finance_mix_chart_svg(finance_entries)
    })
    |> Phoenix.Component.assign(:analytics_highlights, analytics_highlights)
  end

  @doc """
  Legacy chart kept for compatibility and focused tests.
  """
  @spec progress_chart_svg(map()) :: Phoenix.HTML.safe() | nil
  def progress_chart_svg(insights_overview) do
    weekly = safe_period_metrics(insights_overview, :weekly)
    monthly = safe_period_metrics(insights_overview, :monthly)
    annual = safe_period_metrics(insights_overview, :annual)

    data = [
      {"Semanal", weekly.executed, weekly.planned},
      {"Mensal", monthly.executed, monthly.planned},
      {"Anual", annual.executed, annual.planned}
    ]

    dataset = Dataset.new(data, ["periodo", "executado", "planejado"])

    Plot.new(dataset, Contex.BarChart, 640, 260,
      mapping: %{category_col: "periodo", value_cols: ["executado", "planejado"]},
      type: :grouped,
      data_labels: false,
      title: "Progresso por período"
    )
    |> Plot.plot_options(%{legend_setting: :legend_bottom})
    |> Plot.to_svg()
  end

  @spec task_delivery_chart_svg(list(), pos_integer()) :: Phoenix.HTML.safe() | nil
  def task_delivery_chart_svg(tasks, days)
      when is_list(tasks) and is_integer(days) and days > 0 do
    buckets = timeline_buckets(days)

    label_lookup =
      buckets
      |> Map.new(fn bucket -> {bucket.index, bucket.label} end)

    data =
      Enum.map(buckets, fn bucket ->
        {
          bucket.index,
          Enum.count(tasks, &date_inside_bucket?(task_created_on(&1), bucket)),
          Enum.count(tasks, &date_inside_bucket?(task_completed_on(&1), bucket))
        }
      end)

    dataset = Dataset.new(data, ["bucket", "criadas", "concluidas"])

    Plot.new(dataset, Contex.LinePlot, 720, 280,
      mapping: %{x_col: "bucket", y_cols: ["criadas", "concluidas"]},
      smoothed: false,
      custom_x_formatter: fn value ->
        bucket_label_for_axis(value, label_lookup)
      end,
      title: "Ritmo de tarefas: criadas x concluídas"
    )
    |> Plot.plot_options(%{legend_setting: :legend_bottom})
    |> Plot.to_svg()
  end

  def task_delivery_chart_svg(_tasks, _days), do: task_delivery_chart_svg([], 30)

  @spec finance_flow_chart_svg(list(), pos_integer()) :: Phoenix.HTML.safe() | nil
  def finance_flow_chart_svg(finance_entries, days)
      when is_list(finance_entries) and is_integer(days) and days > 0 do
    data =
      timeline_buckets(days)
      |> Enum.map(fn bucket ->
        income_cents =
          finance_entries
          |> Enum.filter(&(&1.kind == :income and date_inside_bucket?(&1.occurred_on, bucket)))
          |> Enum.reduce(0, fn entry, acc -> acc + entry.amount_cents end)

        expense_cents =
          finance_entries
          |> Enum.filter(&(&1.kind == :expense and date_inside_bucket?(&1.occurred_on, bucket)))
          |> Enum.reduce(0, fn entry, acc -> acc + entry.amount_cents end)

        {bucket.label, income_cents, expense_cents}
      end)

    dataset = Dataset.new(data, ["periodo", "receitas", "despesas"])

    Plot.new(dataset, Contex.BarChart, 720, 280,
      mapping: %{category_col: "periodo", value_cols: ["receitas", "despesas"]},
      type: :stacked,
      data_labels: false,
      custom_value_formatter: &money_axis_formatter/1,
      title: "Composição financeira no período"
    )
    |> Plot.plot_options(%{legend_setting: :legend_bottom})
    |> Plot.to_svg()
  end

  def finance_flow_chart_svg(_finance_entries, _days), do: finance_flow_chart_svg([], 30)

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
      |> merge_tail_categories(6)

    data =
      if data == [] do
        [{"Sem despesas", 0}]
      else
        data
      end

    dataset = Dataset.new(data, ["categoria", "valor"])

    Plot.new(dataset, Contex.BarChart, 620, 280,
      mapping: %{category_col: "categoria", value_cols: ["valor"]},
      orientation: :horizontal,
      data_labels: false,
      title: "Top categorias de despesa",
      custom_value_formatter: &money_axis_formatter/1
    )
    |> Plot.to_svg()
  end

  def finance_expense_categories_chart_svg(_), do: finance_expense_categories_chart_svg([])

  @spec task_priority_comparison_chart_svg(list()) :: Phoenix.HTML.safe() | nil
  def task_priority_comparison_chart_svg(tasks) when is_list(tasks) do
    data = [
      priority_bar_row(tasks, :high, "Alta"),
      priority_bar_row(tasks, :medium, "Média"),
      priority_bar_row(tasks, :low, "Baixa")
    ]

    dataset = Dataset.new(data, ["prioridade", "abertas", "concluidas"])

    Plot.new(dataset, Contex.BarChart, 560, 280,
      mapping: %{category_col: "prioridade", value_cols: ["abertas", "concluidas"]},
      type: :grouped,
      data_labels: false,
      title: "Backlog x concluídas por prioridade"
    )
    |> Plot.plot_options(%{legend_setting: :legend_bottom})
    |> Plot.to_svg()
  end

  def task_priority_comparison_chart_svg(_), do: task_priority_comparison_chart_svg([])

  @spec finance_mix_chart_svg(list()) :: Phoenix.HTML.safe() | nil
  def finance_mix_chart_svg(finance_entries) when is_list(finance_entries) do
    data =
      finance_entries
      |> Enum.filter(&(&1.kind == :expense))
      |> Enum.group_by(&expense_profile_label(&1.expense_profile))
      |> Enum.map(fn {label, entries} ->
        {label, Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount_cents end)}
      end)
      |> Enum.sort_by(fn {_label, value} -> -value end)
      |> merge_tail_categories(5)

    data =
      if data == [] do
        [{"Sem despesas", 1}]
      else
        data
      end

    dataset = Dataset.new(data, ["perfil", "valor"])

    Plot.new(dataset, PieChart, 560, 280,
      mapping: %{category_col: "perfil", value_col: "valor"},
      data_labels: false,
      title: "Mix de despesas por natureza",
      colour_palette: ["6bc5d2", "91d29e", "f8d98f", "f3a8a8", "b5b9f3", "cfcfcf"]
    )
    |> Plot.plot_options(%{legend_setting: :legend_right})
    |> Plot.to_svg()
  end

  def finance_mix_chart_svg(_), do: finance_mix_chart_svg([])

  defp safe_period_metrics(insights_overview, period) do
    %{
      executed:
        get_in(insights_overview, [:progress_by_period, period, :executed]) ||
          get_in(insights_overview, [:progress_by_period, to_string(period), :executed]) || 0,
      planned:
        get_in(insights_overview, [:progress_by_period, period, :planned]) ||
          get_in(insights_overview, [:progress_by_period, to_string(period), :planned]) || 0
    }
  end

  defp build_analytics_highlights(tasks, finance_entries, start_on) do
    created_window =
      Enum.count(tasks, fn task ->
        case task_created_on(task) do
          %Date{} = created_on -> Date.compare(created_on, start_on) in [:gt, :eq]
          _ -> false
        end
      end)

    completed_window =
      Enum.count(tasks, fn task ->
        case task_completed_on(task) do
          %Date{} = completed_on -> Date.compare(completed_on, start_on) in [:gt, :eq]
          _ -> false
        end
      end)

    open_high_priority =
      Enum.count(tasks, fn task ->
        task.status != :done and task.priority == :high
      end)

    overdue_open =
      Enum.count(tasks, fn task ->
        task.status != :done and match?(%Date{}, task.due_on) and
          Date.compare(task.due_on, Date.utc_today()) == :lt
      end)

    income_cents =
      finance_entries
      |> Enum.filter(&(&1.kind == :income))
      |> Enum.reduce(0, fn entry, acc -> acc + entry.amount_cents end)

    expense_entries = Enum.filter(finance_entries, &(&1.kind == :expense))

    expense_cents =
      Enum.reduce(expense_entries, 0, fn entry, acc ->
        acc + entry.amount_cents
      end)

    expense_by_category =
      expense_entries
      |> Enum.group_by(&normalize_finance_category(&1.category))
      |> Enum.map(fn {category, entries} ->
        {category, Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount_cents end)}
      end)
      |> Enum.sort_by(fn {_category, total} -> -total end)

    {dominant_expense_category, dominant_expense_cents} =
      List.first(expense_by_category) || {nil, 0}

    completion_rate =
      if created_window == 0 do
        0.0
      else
        Float.round(completed_window / created_window * 100, 1)
      end

    dominant_share =
      if expense_cents <= 0 do
        0.0
      else
        Float.round(dominant_expense_cents / expense_cents * 100, 1)
      end

    expense_mix_top =
      expense_by_category
      |> Enum.take(3)
      |> Enum.map(fn {label, value} ->
        %{
          label: label,
          amount_cents: value,
          share:
            if(expense_cents <= 0,
              do: 0.0,
              else: Float.round(value / expense_cents * 100, 1)
            )
        }
      end)

    %{
      tasks_created_window: created_window,
      tasks_completed_window: completed_window,
      tasks_total_window: length(tasks),
      tasks_completion_rate: completion_rate,
      open_high_priority: open_high_priority,
      overdue_open: overdue_open,
      finance_entries_window: length(finance_entries),
      expense_entries_window: length(expense_entries),
      income_cents: income_cents,
      expense_cents: expense_cents,
      net_cents: income_cents - expense_cents,
      avg_expense_ticket_cents:
        if(expense_entries == [],
          do: 0,
          else: round(expense_cents / length(expense_entries))
        ),
      dominant_expense_category: dominant_expense_category,
      dominant_expense_share: dominant_share,
      expense_mix_top: expense_mix_top
    }
  end

  defp priority_bar_row(tasks, priority, label) do
    open_count =
      Enum.count(tasks, fn task ->
        task.priority == priority and task.status != :done
      end)

    done_count =
      Enum.count(tasks, fn task ->
        task.priority == priority and task.status == :done
      end)

    {label, open_count, done_count}
  end

  defp task_relevant_for_window?(task, start_on) do
    date_candidates = [task_created_on(task), task_completed_on(task), task.due_on]

    Enum.any?(date_candidates, fn
      %Date{} = date -> Date.compare(date, start_on) in [:gt, :eq]
      _ -> false
    end)
  end

  defp task_created_on(task) do
    case Map.get(task, :inserted_at) do
      %DateTime{} = inserted_at -> DateTime.to_date(inserted_at)
      _ -> nil
    end
  end

  defp task_completed_on(task) do
    cond do
      match?(%DateTime{}, task.completed_at) ->
        DateTime.to_date(task.completed_at)

      task.status == :done and match?(%DateTime{}, task.updated_at) ->
        DateTime.to_date(task.updated_at)

      true ->
        nil
    end
  end

  defp timeline_buckets(days) when days <= 30 do
    today = Date.utc_today()
    start_on = Date.add(today, -(days - 1))

    Date.range(start_on, today)
    |> Enum.with_index(1)
    |> Enum.map(fn {date, index} ->
      %{index: index, start_on: date, end_on: date, label: short_date_label(date)}
    end)
  end

  defp timeline_buckets(days) when days <= 120 do
    today = Date.utc_today()
    start_on = Date.add(today, -(days - 1))
    first_week_start = Date.add(start_on, 1 - Date.day_of_week(start_on))

    Stream.iterate(first_week_start, &Date.add(&1, 7))
    |> Enum.take_while(&(Date.compare(&1, today) != :gt))
    |> Enum.map(fn week_start ->
      bucket_start = max_date(week_start, start_on)
      bucket_end = min_date(Date.add(week_start, 6), today)

      if Date.compare(bucket_start, bucket_end) in [:lt, :eq] do
        %{start_on: bucket_start, end_on: bucket_end, label: week_label(bucket_start, bucket_end)}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {bucket, index} -> Map.put(bucket, :index, index) end)
  end

  defp timeline_buckets(days) do
    today = Date.utc_today()
    start_on = Date.add(today, -(days - 1))
    first_month_start = Date.new!(start_on.year, start_on.month, 1)

    Stream.iterate(first_month_start, &next_month_start/1)
    |> Enum.take_while(&(Date.compare(&1, today) != :gt))
    |> Enum.map(fn month_start ->
      bucket_start = max_date(month_start, start_on)
      bucket_end = min_date(end_of_month(month_start), today)

      if Date.compare(bucket_start, bucket_end) in [:lt, :eq] do
        %{start_on: bucket_start, end_on: bucket_end, label: month_label(month_start)}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {bucket, index} -> Map.put(bucket, :index, index) end)
  end

  defp date_inside_bucket?(%Date{} = date, %{start_on: start_on, end_on: end_on}) do
    Date.compare(date, start_on) in [:gt, :eq] and Date.compare(date, end_on) in [:lt, :eq]
  end

  defp date_inside_bucket?(_, _), do: false

  defp merge_tail_categories(rows, limit) when is_list(rows) do
    if length(rows) <= limit do
      rows
    else
      {head, tail} = Enum.split(rows, limit - 1)
      tail_sum = Enum.reduce(tail, 0, fn {_label, value}, acc -> acc + value end)
      head ++ [{"Outras", tail_sum}]
    end
  end

  defp normalize_finance_category(nil), do: "Sem categoria"

  defp normalize_finance_category(category) when is_binary(category) do
    category = String.trim(category)
    if category == "", do: "Sem categoria", else: category
  end

  defp normalize_finance_category(category), do: to_string(category)

  defp expense_profile_label(:fixed), do: "Fixa"
  defp expense_profile_label(:variable), do: "Variável"
  defp expense_profile_label(:recurring_fixed), do: "Recorrente fixa"
  defp expense_profile_label(:recurring_variable), do: "Recorrente variável"
  defp expense_profile_label(nil), do: "Sem classificação"

  defp expense_profile_label(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp expense_profile_label(value) when is_binary(value), do: value
  defp expense_profile_label(_), do: "Sem classificação"

  defp parse_days(value, _fallback) when is_integer(value) and value > 0, do: value

  defp parse_days(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp parse_days(_value, fallback), do: fallback

  defp next_month_start(%Date{year: year, month: 12}), do: Date.new!(year + 1, 1, 1)
  defp next_month_start(%Date{year: year, month: month}), do: Date.new!(year, month + 1, 1)

  defp end_of_month(month_start) do
    month_start
    |> next_month_start()
    |> Date.add(-1)
  end

  defp max_date(a, b) do
    case Date.compare(a, b) do
      :lt -> b
      _ -> a
    end
  end

  defp min_date(a, b) do
    case Date.compare(a, b) do
      :gt -> b
      _ -> a
    end
  end

  defp short_date_label(%Date{} = date) do
    day = date.day |> Integer.to_string() |> String.pad_leading(2, "0")
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{day}/#{month}"
  end

  defp week_label(start_on, end_on),
    do: "#{short_date_label(start_on)}-#{short_date_label(end_on)}"

  defp month_label(%Date{} = date) do
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    year = date.year |> Integer.to_string() |> String.slice(-2, 2)
    "#{month}/#{year}"
  end

  defp bucket_label_for_axis(value, lookup) when is_number(value) and is_map(lookup) do
    rounded = round(value)

    if abs(value - rounded) < 0.001 do
      Map.get(lookup, rounded, "")
    else
      ""
    end
  end

  defp bucket_label_for_axis(_value, _lookup), do: ""

  defp money_axis_formatter(value) when is_number(value) do
    rounded_amount = round(value / 100)
    sign = if rounded_amount < 0, do: "-", else: ""
    integer_part = rounded_amount |> abs() |> Integer.to_string() |> add_thousands_separator()

    "R$ " <> sign <> integer_part
  end

  defp add_thousands_separator(value) when is_binary(value) do
    value
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(".")
    |> String.reverse()
  end
end
