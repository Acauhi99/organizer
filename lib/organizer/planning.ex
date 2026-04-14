defmodule Organizer.Planning do
  @moduledoc """
  Context for day-to-day planning domains: tasks, finance, goals and schedule.
  """

  import Ecto.Query, warn: false

  alias Organizer.Accounts.Scope
  alias Organizer.Planning.Core
  alias Organizer.Planning.FinanceEntry
  alias Organizer.Planning.FixedCost
  alias Organizer.Planning.Goal
  alias Organizer.Planning.ImportantDate
  alias Organizer.Planning.Task
  alias Organizer.Repo

  def list_tasks(%Scope{} = scope, params \\ %{}) do
    with {:ok, user_id} <- scope_user_id(scope) do
      status_filter = Map.get(params, "status") || Map.get(params, :status)
      days = parse_positive_int(Map.get(params, "days") || Map.get(params, :days), 7)

      query =
        from t in Task,
          where: t.user_id == ^user_id,
          order_by: [asc: t.due_on, desc: t.inserted_at]

      query =
        if is_binary(status_filter) and status_filter != "all" do
          from t in query, where: t.status == ^String.to_existing_atom(status_filter)
        else
          query
        end

      query =
        from t in query,
          where: is_nil(t.due_on) or t.due_on <= ^Date.add(Date.utc_today(), days)

      {:ok, Repo.all(query)}
    end
  rescue
    ArgumentError -> {:error, {:validation, %{status: ["is invalid"]}}}
  end

  def create_task(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         {:ok, normalized} <- Core.validate_task_attrs(attrs) do
      %Task{user_id: user_id}
      |> Task.changeset(normalized)
      |> repo_write()
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
         {:ok, normalized} <- Core.validate_finance_entry_attrs(attrs) do
      %FinanceEntry{user_id: user_id}
      |> FinanceEntry.changeset(normalized)
      |> repo_write()
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

  def list_goals(%Scope{} = scope) do
    with {:ok, user_id} <- scope_user_id(scope) do
      query =
        from g in Goal,
          where: g.user_id == ^user_id,
          order_by: [asc: g.status, asc: g.horizon, asc: g.due_on]

      {:ok, Repo.all(query)}
    end
  end

  def create_goal(%Scope{} = scope, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         {:ok, normalized} <- Core.validate_goal_attrs(attrs) do
      %Goal{user_id: user_id}
      |> Goal.changeset(normalized)
      |> repo_write()
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

  def burndown_snapshot(%Scope{} = scope) do
    with {:ok, tasks} <- list_tasks(scope, %{days: 14}) do
      {done, open} = Enum.split_with(tasks, &(&1.status == :done))

      {:ok,
       %{
         total: length(tasks),
         completed: length(done),
         open: length(open)
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
end
