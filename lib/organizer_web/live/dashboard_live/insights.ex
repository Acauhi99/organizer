defmodule OrganizerWeb.DashboardLive.Insights do
  @moduledoc """
  Finance analytics and chart SVG generation for DashboardLive.
  """

  alias Contex.{Dataset, Plot}
  alias Organizer.Planning

  @finance_horizontal_chart_width 900
  @finance_horizontal_chart_height 220
  @finance_composition_chart_width 760
  @finance_composition_chart_height 280
  @finance_horizontal_chart_left_margin 150
  @finance_horizontal_chart_right_margin 46
  @finance_horizontal_chart_bottom_margin 78

  @spec refresh_dashboard_insights(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_dashboard_insights(socket) do
    {:ok, finance_summary} = Planning.finance_summary(socket.assigns.current_scope, 30)

    Phoenix.Component.assign(socket, :finance_summary, finance_summary)
  end

  @spec default_finance_highlights() :: map()
  def default_finance_highlights do
    %{
      finance_entries_window: 0,
      expense_entries_window: 0,
      income_cents: 0,
      expense_cents: 0,
      net_cents: 0,
      avg_expense_ticket_cents: 0,
      dominant_expense_category: nil,
      dominant_expense_share: 0.0,
      expense_composition_top: []
    }
  end

  @spec default_analytics_highlights() :: map()
  def default_analytics_highlights, do: default_finance_highlights()

  @spec load_chart_svgs(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_chart_svgs(socket) do
    finance_days = parse_days(socket.assigns.finance_metrics_filters.days, 30)

    {:ok, finance_entries} =
      Planning.list_finance_entries(socket.assigns.current_scope, %{
        days: finance_days,
        kind: "all",
        expense_profile: "all",
        payment_method: "all"
      })

    finance_highlights = build_finance_highlights(finance_entries)

    socket
    |> Phoenix.Component.assign(:finance_flow_chart, %{
      loading: false,
      chart_svg: finance_flow_chart_svg(finance_entries, finance_days)
    })
    |> Phoenix.Component.assign(:finance_category_chart, %{
      loading: false,
      chart_svg: finance_expense_categories_chart_svg(finance_entries)
    })
    |> Phoenix.Component.assign(:finance_composition_chart, %{
      loading: false,
      chart_svg: finance_composition_chart_svg(finance_entries)
    })
    |> Phoenix.Component.assign(:finance_highlights, finance_highlights)
  end

  @spec finance_flow_chart_svg(list(), pos_integer()) :: Phoenix.HTML.safe() | nil
  def finance_flow_chart_svg(finance_entries, _days) when finance_entries == [], do: nil

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

  def finance_flow_chart_svg(_finance_entries, _days), do: nil

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

    if data == [] do
      nil
    else
      dataset = Dataset.new(data, ["categoria", "valor"])

      Plot.new(
        dataset,
        Contex.BarChart,
        @finance_horizontal_chart_width,
        @finance_horizontal_chart_height,
        mapping: %{category_col: "categoria", value_cols: ["valor"]},
        orientation: :horizontal,
        data_labels: false,
        title: "Top categorias de despesa",
        custom_value_formatter: &money_axis_formatter/1
      )
      |> Plot.plot_options(%{
        left_margin: @finance_horizontal_chart_left_margin,
        right_margin: @finance_horizontal_chart_right_margin,
        bottom_margin: @finance_horizontal_chart_bottom_margin
      })
      |> Plot.to_svg()
    end
  end

  def finance_expense_categories_chart_svg(_), do: nil

  @spec finance_composition_chart_svg(list()) :: Phoenix.HTML.safe() | nil
  def finance_composition_chart_svg(finance_entries) when is_list(finance_entries) do
    data =
      finance_entries
      |> Enum.filter(&(&1.kind == :expense))
      |> Enum.group_by(&expense_profile_label(&1.expense_profile))
      |> Enum.map(fn {label, entries} ->
        {label, Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount_cents end)}
      end)
      |> Enum.sort_by(fn {_label, value} -> -value end)
      |> merge_tail_categories(5)

    if data == [] do
      nil
    else
      dataset = Dataset.new(data, ["perfil", "valor"])

      Plot.new(
        dataset,
        Contex.BarChart,
        @finance_composition_chart_width,
        @finance_composition_chart_height,
        mapping: %{category_col: "perfil", value_cols: ["valor"]},
        orientation: :horizontal,
        data_labels: false,
        title: "Composição de despesas por natureza",
        custom_value_formatter: &money_axis_formatter/1
      )
      |> Plot.plot_options(%{
        left_margin: @finance_horizontal_chart_left_margin,
        right_margin: @finance_horizontal_chart_right_margin,
        bottom_margin: @finance_horizontal_chart_bottom_margin
      })
      |> Plot.to_svg()
    end
  end

  def finance_composition_chart_svg(_), do: nil

  @spec finance_mix_chart_svg(list()) :: Phoenix.HTML.safe() | nil
  def finance_mix_chart_svg(entries), do: finance_composition_chart_svg(entries)

  defp build_finance_highlights(finance_entries) do
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

    expense_by_profile =
      expense_entries
      |> Enum.group_by(&expense_profile_label(&1.expense_profile))
      |> Enum.map(fn {label, entries} ->
        {label, Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount_cents end)}
      end)
      |> Enum.sort_by(fn {_label, total} -> -total end)

    {dominant_expense_category, dominant_expense_cents} =
      List.first(expense_by_category) || {nil, 0}

    dominant_share =
      if expense_cents <= 0 do
        0.0
      else
        Float.round(dominant_expense_cents / expense_cents * 100, 1)
      end

    expense_composition_top =
      expense_by_profile
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
      expense_composition_top: expense_composition_top
    }
  end

  defp timeline_buckets(days) when days <= 30 do
    today = Date.utc_today()
    start_on = Date.add(today, -(days - 1))

    Date.range(start_on, today)
    |> Enum.map(fn date ->
      %{start_on: date, end_on: date, label: short_date_label(date)}
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
