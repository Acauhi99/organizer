defmodule OrganizerWeb.DashboardLive.Filters do
  @moduledoc """
  Módulo puro de filtros para o DashboardLive.

  Encapsula todas as constantes de valores permitidos e as funções de
  normalização/sanitização de filtros para tarefas, finanças, metas e analytics.
  Sem efeitos colaterais e sem dependências externas.
  """

  @max_search_length 100

  @task_status_filters ["all", "todo", "in_progress", "done"]
  @task_priority_filters ["all", "low", "medium", "high"]
  @task_days_filters ["7", "14", "30"]
  @finance_days_filters ["7", "30", "90"]
  @finance_kind_filters ["all", "income", "expense"]
  @finance_expense_profile_filters ["all", "fixed", "variable"]
  @finance_payment_method_filters ["all", "credit", "debit"]
  @goal_status_filters ["all", "active", "paused", "done"]
  @goal_horizon_filters ["all", "short", "medium", "long"]
  @analytics_days_filters ["7", "15", "30", "90", "365"]
  @analytics_capacity_filters ["5", "10", "15", "20", "30"]

  @spec default_task_filters() :: map()
  def default_task_filters do
    %{status: "all", priority: "all", days: "14", q: ""}
  end

  @spec default_finance_filters() :: map()
  def default_finance_filters do
    %{
      days: "30",
      kind: "all",
      expense_profile: "all",
      payment_method: "all",
      category: "",
      q: "",
      min_amount_cents: "",
      max_amount_cents: ""
    }
  end

  @spec default_goal_filters() :: map()
  def default_goal_filters do
    %{status: "all", horizon: "all", days: "365", progress_min: "", progress_max: "", q: ""}
  end

  @spec default_analytics_filters() :: map()
  def default_analytics_filters do
    %{days: "30", planned_capacity: "10"}
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
      days: Map.get(filters, "days"),
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

  @spec normalize_goal_filters(map()) :: map()
  def normalize_goal_filters(filters) when is_map(filters) do
    %{
      status: Map.get(filters, "status"),
      horizon: Map.get(filters, "horizon"),
      days: Map.get(filters, "days"),
      progress_min: Map.get(filters, "progress_min"),
      progress_max: Map.get(filters, "progress_max"),
      q: Map.get(filters, "q")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  @spec normalize_analytics_filters(map()) :: map()
  def normalize_analytics_filters(filters) when is_map(filters) do
    %{
      days: Map.get(filters, "days"),
      planned_capacity: Map.get(filters, "planned_capacity")
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
    |> Map.update(:days, "30", fn value ->
      if value in @finance_days_filters, do: value, else: "30"
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
    |> Map.update(:min_amount_cents, "", fn value ->
      if is_binary(value) and String.trim(value) != "" do
        case Integer.parse(String.trim(value)) do
          {n, ""} when n >= 0 -> Integer.to_string(n)
          _ -> ""
        end
      else
        ""
      end
    end)
    |> Map.update(:max_amount_cents, "", fn value ->
      if is_binary(value) and String.trim(value) != "" do
        case Integer.parse(String.trim(value)) do
          {n, ""} when n >= 0 -> Integer.to_string(n)
          _ -> ""
        end
      else
        ""
      end
    end)
  end

  @spec sanitize_goal_filters(map()) :: map()
  def sanitize_goal_filters(filters) do
    filters
    |> Map.update(:status, "all", fn value ->
      if value in @goal_status_filters, do: value, else: "all"
    end)
    |> Map.update(:horizon, "all", fn value ->
      if value in @goal_horizon_filters, do: value, else: "all"
    end)
    |> Map.update(:days, "365", fn value ->
      if is_binary(value) and String.trim(value) != "" do
        case Integer.parse(String.trim(value)) do
          {n, ""} when n >= 1 and n <= 3650 -> Integer.to_string(n)
          _ -> "365"
        end
      else
        "365"
      end
    end)
    |> Map.update(:progress_min, "", fn value ->
      if is_binary(value) and String.trim(value) != "" do
        case Integer.parse(String.trim(value)) do
          {n, ""} when n >= 0 and n <= 100 -> Integer.to_string(n)
          _ -> ""
        end
      else
        ""
      end
    end)
    |> Map.update(:progress_max, "", fn value ->
      if is_binary(value) and String.trim(value) != "" do
        case Integer.parse(String.trim(value)) do
          {n, ""} when n >= 0 and n <= 100 -> Integer.to_string(n)
          _ -> ""
        end
      else
        ""
      end
    end)
    |> Map.update(:q, "", fn value ->
      if is_binary(value) do
        value |> String.trim() |> String.slice(0, @max_search_length)
      else
        ""
      end
    end)
    |> swap_progress_if_inverted()
  end

  defp swap_progress_if_inverted(filters) do
    with min_str when min_str != "" <- Map.get(filters, :progress_min, ""),
         max_str when max_str != "" <- Map.get(filters, :progress_max, ""),
         {min, ""} <- Integer.parse(min_str),
         {max, ""} <- Integer.parse(max_str),
         true <- min > max do
      filters
      |> Map.put(:progress_min, Integer.to_string(max))
      |> Map.put(:progress_max, Integer.to_string(min))
    else
      _ -> filters
    end
  end

  @spec sanitize_analytics_filters(map()) :: map()
  def sanitize_analytics_filters(filters) do
    filters
    |> Map.update(:days, "30", fn value ->
      if value in @analytics_days_filters, do: value, else: "30"
    end)
    |> Map.update(:planned_capacity, "10", fn value ->
      if value in @analytics_capacity_filters, do: value, else: "10"
    end)
  end
end
