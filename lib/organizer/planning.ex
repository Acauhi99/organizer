defmodule Organizer.Planning do
  @moduledoc """
  Context for day-to-day planning domains: tasks, finance, goals and schedule.
  """

  import Ecto.Query, warn: false

  alias Organizer.Accounts.Scope
  alias Organizer.Planning.Analytics
  alias Organizer.Planning.AttributeValidation
  alias Organizer.Planning.FinanceEntry
  alias Organizer.Planning.FixedCost
  alias Organizer.Planning.Goal
  alias Organizer.Planning.ImportantDate
  alias Organizer.Planning.Task
  alias Organizer.Repo

  def list_tasks(%Scope{} = scope, params \\ %{}) do
    with {:ok, user_id} <- scope_user_id(scope) do
      status_filter = Map.get(params, "status") || Map.get(params, :status)
      priority_filter = Map.get(params, "priority") || Map.get(params, :priority)
      days = parse_positive_int(Map.get(params, "days") || Map.get(params, :days), 7)

      with {:ok, status_filter} <- enum_filter(status_filter, Task.statuses(), :status),
           {:ok, priority_filter} <- enum_filter(priority_filter, Task.priorities(), :priority) do
        query =
          from t in Task,
            where: t.user_id == ^user_id,
            order_by: [asc: t.due_on, desc: t.inserted_at]

        query =
          if is_atom(status_filter) and not is_nil(status_filter) do
            from t in query, where: t.status == ^status_filter
          else
            query
          end

        query =
          if is_atom(priority_filter) and not is_nil(priority_filter) do
            from t in query, where: t.priority == ^priority_filter
          else
            query
          end

        query =
          from t in query,
            where: is_nil(t.due_on) or t.due_on <= ^Date.add(Date.utc_today(), days)

        {:ok, Repo.all(query)}
      end
    end
  end

  def create_task(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
          {:ok, normalized} <- AttributeValidation.validate_task_attrs(attrs) do
      %Task{user_id: user_id}
      |> Task.changeset(normalized)
      |> repo_write()
    end
  end

  def get_task(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- Repo.get_by(Task, id: id, user_id: user_id) do
      {:ok, task}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def update_task(%Scope{} = scope, id, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- Repo.get_by(Task, id: id, user_id: user_id) do
      task
      |> Task.changeset(attrs)
      |> repo_write()
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def delete_task(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- Repo.get_by(Task, id: id, user_id: user_id),
         {:ok, task} <- Repo.delete(task) do
      {:ok, task}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def list_finance_entries(%Scope{} = scope, params \\ %{}) do
    with {:ok, user_id} <- scope_user_id(scope) do
      days = parse_positive_int(Map.get(params, "days") || Map.get(params, :days), 30)
      start_on = Date.add(Date.utc_today(), -days)

      query =
        from f in FinanceEntry,
          where: f.user_id == ^user_id and f.occurred_on >= ^start_on,
          order_by: [desc: f.occurred_on, desc: f.inserted_at]

      {:ok, Repo.all(query)}
    end
  end

  def create_finance_entry(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
          {:ok, normalized} <- AttributeValidation.validate_finance_entry_attrs(attrs) do
      %FinanceEntry{user_id: user_id}
      |> FinanceEntry.changeset(normalized)
      |> repo_write()
    end
  end

  def get_finance_entry(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %FinanceEntry{} = entry <- Repo.get_by(FinanceEntry, id: id, user_id: user_id) do
      {:ok, entry}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def update_finance_entry(%Scope{} = scope, id, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         %FinanceEntry{} = entry <- Repo.get_by(FinanceEntry, id: id, user_id: user_id),
          {:ok, normalized} <- AttributeValidation.validate_finance_entry_attrs(attrs) do
      entry
      |> FinanceEntry.changeset(normalized)
      |> repo_write()
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def delete_finance_entry(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %FinanceEntry{} = entry <- Repo.get_by(FinanceEntry, id: id, user_id: user_id),
         {:ok, entry} <- Repo.delete(entry) do
      {:ok, entry}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def finance_summary(%Scope{} = scope, days \\ 30) do
    with {:ok, entries} <- list_finance_entries(scope, %{days: days}) do
      summary =
        Enum.reduce(entries, %{income_cents: 0, expense_cents: 0}, fn entry, acc ->
          case entry.kind do
            :income -> %{acc | income_cents: acc.income_cents + entry.amount_cents}
            :expense -> %{acc | expense_cents: acc.expense_cents + entry.amount_cents}
          end
        end)

      {:ok, Map.put(summary, :balance_cents, summary.income_cents - summary.expense_cents)}
    end
  end

  def list_goals(%Scope{} = scope, params \\ %{}) do
    with {:ok, user_id} <- scope_user_id(scope) do
      status_filter = Map.get(params, "status") || Map.get(params, :status)
      horizon_filter = Map.get(params, "horizon") || Map.get(params, :horizon)

      with {:ok, status_filter} <- enum_filter(status_filter, Goal.statuses(), :status),
           {:ok, horizon_filter} <- enum_filter(horizon_filter, Goal.horizons(), :horizon) do
        query =
          from g in Goal,
            where: g.user_id == ^user_id,
            order_by: [asc: g.status, asc: g.horizon, asc: g.due_on]

        query =
          if is_atom(status_filter) and not is_nil(status_filter) do
            from g in query, where: g.status == ^status_filter
          else
            query
          end

        query =
          if is_atom(horizon_filter) and not is_nil(horizon_filter) do
            from g in query, where: g.horizon == ^horizon_filter
          else
            query
          end

        {:ok, Repo.all(query)}
      end
    end
  end

  def create_goal(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
          {:ok, normalized} <- AttributeValidation.validate_goal_attrs(attrs) do
      %Goal{user_id: user_id}
      |> Goal.changeset(normalized)
      |> repo_write()
    end
  end

  def get_goal(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Goal{} = goal <- Repo.get_by(Goal, id: id, user_id: user_id) do
      {:ok, goal}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def update_goal(%Scope{} = scope, id, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Goal{} = goal <- Repo.get_by(Goal, id: id, user_id: user_id),
          {:ok, normalized} <- AttributeValidation.validate_goal_attrs(attrs) do
      goal
      |> Goal.changeset(normalized)
      |> repo_write()
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def delete_goal(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Goal{} = goal <- Repo.get_by(Goal, id: id, user_id: user_id),
         {:ok, goal} <- Repo.delete(goal) do
      {:ok, goal}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def list_important_dates(%Scope{} = scope, days \\ 30) do
    with {:ok, user_id} <- scope_user_id(scope) do
      end_on = Date.add(Date.utc_today(), days)

      query =
        from d in ImportantDate,
          where: d.user_id == ^user_id and d.date <= ^end_on,
          order_by: [asc: d.date]

      {:ok, Repo.all(query)}
    end
  end

  def create_important_date(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope) do
      %ImportantDate{user_id: user_id}
      |> ImportantDate.changeset(attrs)
      |> repo_write()
    end
  end

  def get_important_date(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %ImportantDate{} = date <- Repo.get_by(ImportantDate, id: id, user_id: user_id) do
      {:ok, date}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def update_important_date(%Scope{} = scope, id, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         %ImportantDate{} = date <- Repo.get_by(ImportantDate, id: id, user_id: user_id) do
      date
      |> ImportantDate.changeset(attrs)
      |> repo_write()
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def delete_important_date(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %ImportantDate{} = date <- Repo.get_by(ImportantDate, id: id, user_id: user_id),
         {:ok, date} <- Repo.delete(date) do
      {:ok, date}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def list_fixed_costs(%Scope{} = scope) do
    with {:ok, user_id} <- scope_user_id(scope) do
      query = from c in FixedCost, where: c.user_id == ^user_id, order_by: [asc: c.billing_day]
      {:ok, Repo.all(query)}
    end
  end

  def create_fixed_cost(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope) do
      %FixedCost{user_id: user_id}
      |> FixedCost.changeset(attrs)
      |> repo_write()
    end
  end

  def get_fixed_cost(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %FixedCost{} = cost <- Repo.get_by(FixedCost, id: id, user_id: user_id) do
      {:ok, cost}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def update_fixed_cost(%Scope{} = scope, id, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         %FixedCost{} = cost <- Repo.get_by(FixedCost, id: id, user_id: user_id) do
      cost
      |> FixedCost.changeset(attrs)
      |> repo_write()
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def delete_fixed_cost(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %FixedCost{} = cost <- Repo.get_by(FixedCost, id: id, user_id: user_id),
         {:ok, cost} <- Repo.delete(cost) do
      {:ok, cost}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def burndown_snapshot(%Scope{} = scope, opts \\ %{}) do
    days = parse_positive_int(get_opt(opts, :days), 14)
    planned_capacity = parse_non_negative_int(get_opt(opts, :planned_capacity), 10)

    with {:ok, tasks} <- list_tasks(scope, %{days: days}) do
      {done, open} = Enum.split_with(tasks, &(&1.status == :done))

      analytics = Analytics.workload_capacity_snapshot(tasks, planned_capacity)

      {:ok,
       Map.merge(
         %{
           total: length(tasks),
           completed: length(done),
           open: length(open)
         },
         analytics
       )}
    end
  end

  def analytics_overview(%Scope{} = scope, opts \\ %{}) do
    days = parse_positive_int(get_opt(opts, :days), 365)
    planned_capacity = parse_non_negative_int(get_opt(opts, :planned_capacity), 10)

    with {:ok, tasks} <- list_tasks(scope, %{days: days}) do
      {:ok,
       %{
         progress_by_period: Analytics.progress_by_period(tasks),
         workload_capacity: Analytics.workload_capacity_snapshot(tasks, planned_capacity),
         burnout_risk_assessment: Analytics.burnout_risk_assessment(tasks)
       }}
    end
  end

  defp repo_write(changeset) do
    case Repo.insert_or_update(changeset) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> {:error, {:validation, changeset_errors(changeset)}}
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp scope_user_id(%Scope{user: %{id: user_id}}), do: {:ok, user_id}
  defp scope_user_id(_), do: {:error, :unauthorized}

  defp parse_positive_int(nil, default), do: default
  defp parse_positive_int("", default), do: default

  defp parse_positive_int(value, _default) when is_integer(value) and value > 0, do: value

  defp parse_positive_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp parse_positive_int(_, default), do: default

  defp parse_non_negative_int(nil, default), do: default
  defp parse_non_negative_int("", default), do: default

  defp parse_non_negative_int(value, _default) when is_integer(value) and value >= 0, do: value

  defp parse_non_negative_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> default
    end
  end

  defp parse_non_negative_int(_, default), do: default

  defp get_opt(opts, key) when is_map(opts), do: Map.get(opts, key) || Map.get(opts, Atom.to_string(key))
  defp get_opt(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp get_opt(_opts, _key), do: nil

  defp enum_filter(nil, _allowed_atoms, _field), do: {:ok, nil}
  defp enum_filter("", _allowed_atoms, _field), do: {:ok, nil}
  defp enum_filter("all", _allowed_atoms, _field), do: {:ok, nil}

  defp enum_filter(value, allowed_atoms, field) when is_atom(value) do
    if value in allowed_atoms do
      {:ok, value}
    else
      {:error, {:validation, %{field => ["is invalid"]}}}
    end
  end

  defp enum_filter(value, allowed_atoms, field) when is_binary(value) do
    case Enum.find(allowed_atoms, &(Atom.to_string(&1) == value)) do
      nil -> {:error, {:validation, %{field => ["is invalid"]}}}
      atom -> {:ok, atom}
    end
  end

  defp enum_filter(_value, _allowed_atoms, field), do: {:error, {:validation, %{field => ["is invalid"]}}}
end
