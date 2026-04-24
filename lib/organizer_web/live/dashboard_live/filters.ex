defmodule OrganizerWeb.DashboardLive.Filters do
  @moduledoc """
  Módulo puro de filtros para o DashboardLive.

  Encapsula todas as constantes de valores permitidos e as funções de
  normalização/sanitização de filtros para tarefas, finanças e analytics.
  Sem efeitos colaterais e sem dependências externas.
  """

  alias Organizer.DateSupport

  @max_search_length 100

  @task_status_filters ["all", "todo", "in_progress", "done"]
  @task_priority_filters ["all", "low", "medium", "high"]
  @task_days_filters ["7", "14", "30"]

  @finance_period_mode_filters ["rolling", "specific_date", "month", "range", "weekday"]
  @finance_days_filters ["7", "30", "90", "365"]
  @finance_kind_filters ["all", "income", "expense"]
  @finance_expense_profile_filters [
    "all",
    "fixed",
    "variable",
    "recurring_fixed",
    "recurring_variable"
  ]
  @finance_payment_method_filters ["all", "credit", "debit"]
  @finance_weekday_filters ["all", "0", "1", "2", "3", "4", "5", "6"]
  @finance_sort_by_filters ["date_desc", "date_asc", "amount_desc", "amount_asc", "category_asc"]

  @task_metrics_days_filters ["7", "15", "30", "90", "365"]
  @task_metrics_capacity_filters ["5", "10", "15", "20", "30"]
  @finance_metrics_days_filters ["7", "30", "90", "365"]

  @spec default_task_filters() :: map()
  def default_task_filters do
    %{status: "all", priority: "all", days: "14", q: ""}
  end

  @spec default_finance_filters() :: map()
  def default_finance_filters do
    %{
      period_mode: "rolling",
      days: "30",
      month: "",
      occurred_on: "",
      occurred_from: "",
      occurred_to: "",
      weekday: "all",
      sort_by: "date_desc",
      kind: "all",
      expense_profile: "all",
      payment_method: "all",
      category: "",
      q: "",
      min_amount_cents: "",
      max_amount_cents: ""
    }
  end

  @spec default_task_metrics_filters() :: map()
  def default_task_metrics_filters do
    %{days: "30", planned_capacity: "10"}
  end

  @spec default_finance_metrics_filters() :: map()
  def default_finance_metrics_filters do
    %{days: "30"}
  end

  @spec normalize_task_filters(map()) :: map()
  def normalize_task_filters(filters) when is_map(filters) do
    %{
      status: Map.get(filters, "status"),
      priority: Map.get(filters, "priority"),
      days: Map.get(filters, "days"),
      q: Map.get(filters, "q")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  @spec normalize_finance_filters(map()) :: map()
  def normalize_finance_filters(filters) when is_map(filters) do
    %{
      period_mode: Map.get(filters, "period_mode"),
      days: Map.get(filters, "days"),
      month: Map.get(filters, "month"),
      occurred_on: Map.get(filters, "occurred_on"),
      occurred_from: Map.get(filters, "occurred_from"),
      occurred_to: Map.get(filters, "occurred_to"),
      weekday: Map.get(filters, "weekday"),
      sort_by: Map.get(filters, "sort_by"),
      kind: Map.get(filters, "kind"),
      expense_profile: Map.get(filters, "expense_profile"),
      payment_method: Map.get(filters, "payment_method"),
      category: Map.get(filters, "category"),
      q: Map.get(filters, "q"),
      min_amount_cents: Map.get(filters, "min_amount_cents"),
      max_amount_cents: Map.get(filters, "max_amount_cents")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  @spec normalize_task_metrics_filters(map()) :: map()
  def normalize_task_metrics_filters(filters) when is_map(filters) do
    %{
      days: Map.get(filters, "days"),
      planned_capacity: Map.get(filters, "planned_capacity")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  @spec normalize_finance_metrics_filters(map()) :: map()
  def normalize_finance_metrics_filters(filters) when is_map(filters) do
    %{
      days: Map.get(filters, "days")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  @spec sanitize_task_filters(map()) :: map()
  def sanitize_task_filters(filters) do
    filters
    |> Map.update(:status, "all", fn value ->
      if value in @task_status_filters, do: value, else: "all"
    end)
    |> Map.update(:priority, "all", fn value ->
      if value in @task_priority_filters, do: value, else: "all"
    end)
    |> Map.update(:days, "14", fn value ->
      if value in @task_days_filters, do: value, else: "14"
    end)
    |> Map.update(:q, "", fn value ->
      if is_binary(value) do
        value |> String.trim() |> String.slice(0, @max_search_length)
      else
        ""
      end
    end)
  end

  @spec sanitize_finance_filters(map()) :: map()
  def sanitize_finance_filters(filters) do
    filters
    |> Map.update(:period_mode, "rolling", fn value ->
      if value in @finance_period_mode_filters, do: value, else: "rolling"
    end)
    |> Map.update(:days, "30", fn value ->
      if value in @finance_days_filters, do: value, else: "30"
    end)
    |> Map.update(:month, "", &sanitize_month_input/1)
    |> Map.update(:occurred_on, "", &sanitize_date_input/1)
    |> Map.update(:occurred_from, "", &sanitize_date_input/1)
    |> Map.update(:occurred_to, "", &sanitize_date_input/1)
    |> Map.update(:weekday, "all", fn value ->
      if value in @finance_weekday_filters, do: value, else: "all"
    end)
    |> Map.update(:sort_by, "date_desc", fn value ->
      if value in @finance_sort_by_filters, do: value, else: "date_desc"
    end)
    |> Map.update(:kind, "all", fn value ->
      if value in @finance_kind_filters, do: value, else: "all"
    end)
    |> Map.update(:expense_profile, "all", fn value ->
      if value in @finance_expense_profile_filters, do: value, else: "all"
    end)
    |> Map.update(:payment_method, "all", fn value ->
      if value in @finance_payment_method_filters, do: value, else: "all"
    end)
    |> Map.update(:category, "", fn value ->
      if is_binary(value), do: String.trim(value), else: ""
    end)
    |> Map.update(:q, "", fn value ->
      if is_binary(value) do
        value |> String.trim() |> String.slice(0, @max_search_length)
      else
        ""
      end
    end)
    |> Map.update(:min_amount_cents, "", &sanitize_non_negative_integer_string/1)
    |> Map.update(:max_amount_cents, "", &sanitize_non_negative_integer_string/1)
  end

  @spec sanitize_task_metrics_filters(map()) :: map()
  def sanitize_task_metrics_filters(filters) do
    filters
    |> Map.update(:days, "30", fn value ->
      if value in @task_metrics_days_filters, do: value, else: "30"
    end)
    |> Map.update(:planned_capacity, "10", fn value ->
      if value in @task_metrics_capacity_filters, do: value, else: "10"
    end)
  end

  @spec sanitize_finance_metrics_filters(map()) :: map()
  def sanitize_finance_metrics_filters(filters) do
    filters
    |> Map.update(:days, "30", fn value ->
      if value in @finance_metrics_days_filters, do: value, else: "30"
    end)
  end

  @spec default_analytics_filters() :: map()
  def default_analytics_filters, do: default_task_metrics_filters()

  @spec normalize_analytics_filters(map()) :: map()
  def normalize_analytics_filters(filters), do: normalize_task_metrics_filters(filters)

  @spec sanitize_analytics_filters(map()) :: map()
  def sanitize_analytics_filters(filters), do: sanitize_task_metrics_filters(filters)

  defp sanitize_non_negative_integer_string(value) do
    if is_binary(value) and String.trim(value) != "" do
      case Integer.parse(String.trim(value)) do
        {n, ""} when n >= 0 -> Integer.to_string(n)
        _ -> ""
      end
    else
      ""
    end
  end

  defp sanitize_month_input(value) when is_binary(value) do
    cleaned = String.trim(value)

    case DateSupport.parse_month_year(cleaned) do
      {:ok, {month_start, _month_end}} -> DateSupport.format_month_year(month_start)
      :error -> ""
    end
  end

  defp sanitize_month_input(_value), do: ""

  defp sanitize_date_input(value) when is_binary(value) do
    cleaned = String.trim(value)

    case DateSupport.parse_date(cleaned) do
      {:ok, date} -> DateSupport.format_pt_br(date)
      :error -> ""
    end
  end

  defp sanitize_date_input(_value), do: ""
end
