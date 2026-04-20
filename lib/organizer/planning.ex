defmodule Organizer.Planning do
  @moduledoc """
  Context for day-to-day planning domains: tasks, finance, goals and schedule.
  """

  import Ecto.Query, warn: false

  alias Organizer.Accounts.Scope
  alias Organizer.Planning.Analytics
  alias Organizer.Planning.AttributeValidation
  alias Organizer.Planning.FilterNormalization
  alias Organizer.Planning.FinanceEntry
  alias Organizer.Planning.FixedCost
  alias Organizer.Planning.Goal
  alias Organizer.Planning.ImportantDate
  alias Organizer.Planning.Task
  alias Organizer.Planning.TaskChecklistItem
  alias Organizer.Repo

  def list_tasks(%Scope{} = scope, params \\ %{}) do
    with {:ok, user_id} <- scope_user_id(scope) do
      status_filter = Map.get(params, "status") || Map.get(params, :status)
      priority_filter = Map.get(params, "priority") || Map.get(params, :priority)

      days =
        parse_positive_integer_or_default(Map.get(params, "days") || Map.get(params, :days), 7)

      query_text = Map.get(params, "q") || Map.get(params, :q) || ""

      with {:ok, status_filter} <-
             parse_enum_filter_value(status_filter, Task.statuses(), :status),
           {:ok, priority_filter} <-
             parse_enum_filter_value(priority_filter, Task.priorities(), :priority) do
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

        # Text search on title and notes
        safe_query = query_text |> String.trim() |> String.slice(0, 100)

        query =
          if safe_query != "" do
            search_pattern = "%#{safe_query}%"

            from t in query,
              where: ilike(t.title, ^search_pattern) or ilike(t.notes, ^search_pattern)
          else
            query
          end

        checklist_query =
          from i in TaskChecklistItem,
            order_by: [asc: i.position, asc: i.inserted_at]

        query =
          from t in query,
            preload: [checklist_items: ^checklist_query]

        {:ok, Repo.all(query)}
      end
    end
  end

  def create_task(%Scope{} = scope, attrs) when is_map(attrs) do
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           {:ok, normalized} <- AttributeValidation.validate_task_attrs(attrs) do
        %Task{user_id: user_id}
        |> Task.changeset(normalized)
        |> persist_changeset()
      end

    with {:ok, _task} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
  end

  def get_task(%Scope{} = scope, id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- task_with_checklist_items_query(user_id, id) |> Repo.one() do
      {:ok, task}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def update_task(%Scope{} = scope, id, attrs) when is_map(attrs) do
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           %Task{} = task <- Repo.get_by(Task, id: id, user_id: user_id),
           merged = merge_task_defaults(task, attrs),
           {:ok, normalized} <- AttributeValidation.validate_task_attrs(merged) do
        task
        |> Task.changeset(normalized)
        |> persist_changeset()
      else
        nil -> {:error, :not_found}
        {:error, _reason} = error -> error
      end

    with {:ok, _task} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
  end

  def delete_task(%Scope{} = scope, id) do
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           %Task{} = task <- Repo.get_by(Task, id: id, user_id: user_id),
           {:ok, task} <- Repo.delete(task) do
        {:ok, task}
      else
        nil -> {:error, :not_found}
        {:error, _reason} = error -> error
      end

    with {:ok, _task} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
  end

  def add_task_checklist_item(%Scope{} = scope, task_id, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- Repo.get_by(Task, id: task_id, user_id: user_id),
         {:ok, label} <- validate_checklist_label(attrs),
         {:ok, item} <- create_task_checklist_item(task, label),
         {:ok, _task} <- sync_task_status_with_checklist(scope, task.id) do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
      {:ok, item}
    else
      nil ->
        {:error, :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  def update_task_checklist_item(%Scope{} = scope, task_id, item_id, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- Repo.get_by(Task, id: task_id, user_id: user_id),
         %TaskChecklistItem{} = item <-
           Repo.get_by(TaskChecklistItem, id: item_id, task_id: task.id),
         {:ok, label} <- validate_checklist_label(attrs),
         {:ok, item} <-
           item |> TaskChecklistItem.changeset(%{label: label}) |> persist_changeset() do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
      {:ok, item}
    else
      nil ->
        {:error, :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  def toggle_task_checklist_item(%Scope{} = scope, task_id, item_id, checked_value) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- Repo.get_by(Task, id: task_id, user_id: user_id),
         %TaskChecklistItem{} = item <-
           Repo.get_by(TaskChecklistItem, id: item_id, task_id: task.id),
         {:ok, checked?} <- parse_checked_flag(checked_value),
         {:ok, item} <- update_checklist_item_checked(item, checked?),
         {:ok, _task} <- sync_task_status_with_checklist(scope, task.id) do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
      {:ok, item}
    else
      nil ->
        {:error, :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  def delete_task_checklist_item(%Scope{} = scope, task_id, item_id) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- Repo.get_by(Task, id: task_id, user_id: user_id),
         %TaskChecklistItem{} = item <-
           Repo.get_by(TaskChecklistItem, id: item_id, task_id: task.id),
         {:ok, _deleted} <- Repo.delete(item),
         {:ok, _task} <- sync_task_status_with_checklist(scope, task.id) do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
      :ok
    else
      nil ->
        {:error, :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  def list_finance_entries(%Scope{} = scope, params \\ %{}) do
    with {:ok, user_id} <- scope_user_id(scope) do
      days =
        parse_positive_integer_or_default(Map.get(params, "days") || Map.get(params, :days), 30)

      start_on = Date.add(Date.utc_today(), -days)

      kind_filter = Map.get(params, "kind") || Map.get(params, :kind)

      expense_profile_filter =
        Map.get(params, "expense_profile") || Map.get(params, :expense_profile)

      payment_method_filter =
        Map.get(params, "payment_method") || Map.get(params, :payment_method)

      category_filter = Map.get(params, "category") || Map.get(params, :category) || ""
      query_text = Map.get(params, "q") || Map.get(params, :q) || ""

      min_amount_cents =
        parse_non_negative_integer_or_default(
          Map.get(params, "min_amount_cents") || Map.get(params, :min_amount_cents),
          0
        )

      max_amount_cents =
        parse_non_negative_integer_or_default(
          Map.get(params, "max_amount_cents") || Map.get(params, :max_amount_cents),
          nil
        )

      with {:ok, kind_filter} <-
             parse_enum_filter_value(kind_filter, FinanceEntry.kinds(), :kind),
           {:ok, expense_profile_filter} <-
             parse_enum_filter_value(
               expense_profile_filter,
               FinanceEntry.expense_profiles(),
               :expense_profile
             ),
           {:ok, payment_method_filter} <-
             parse_enum_filter_value(
               payment_method_filter,
               FinanceEntry.payment_methods(),
               :payment_method
             ) do
        query =
          from f in FinanceEntry,
            where: f.user_id == ^user_id and f.occurred_on >= ^start_on,
            order_by: [desc: f.occurred_on, desc: f.inserted_at]

        query =
          if is_atom(kind_filter) and not is_nil(kind_filter) do
            from f in query, where: f.kind == ^kind_filter
          else
            query
          end

        query =
          if is_atom(expense_profile_filter) and not is_nil(expense_profile_filter) do
            from f in query, where: f.expense_profile == ^expense_profile_filter
          else
            query
          end

        query =
          if is_atom(payment_method_filter) and not is_nil(payment_method_filter) do
            from f in query, where: f.payment_method == ^payment_method_filter
          else
            query
          end

        query =
          if is_binary(category_filter) and String.trim(category_filter) != "" do
            search_pattern = "%#{String.trim(category_filter)}%"
            from f in query, where: ilike(f.category, ^search_pattern)
          else
            query
          end

        safe_query = query_text |> String.trim() |> String.slice(0, 100)

        query =
          if safe_query != "" do
            search_pattern = "%#{safe_query}%"

            from f in query,
              where: ilike(f.description, ^search_pattern) or ilike(f.category, ^search_pattern)
          else
            query
          end

        query =
          from f in query,
            where: f.amount_cents >= ^min_amount_cents

        query =
          if is_integer(max_amount_cents) and max_amount_cents >= 0 do
            from f in query, where: f.amount_cents <= ^max_amount_cents
          else
            query
          end

        {:ok, Repo.all(query)}
      end
    end
  end

  def create_finance_entry(%Scope{} = scope, attrs) when is_map(attrs) do
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           {:ok, normalized} <- AttributeValidation.validate_finance_entry_attrs(attrs) do
        %FinanceEntry{user_id: user_id}
        |> FinanceEntry.changeset(normalized)
        |> persist_changeset()
      end

    with {:ok, _entry} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
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
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           %FinanceEntry{} = entry <- Repo.get_by(FinanceEntry, id: id, user_id: user_id),
           {:ok, normalized} <- AttributeValidation.validate_finance_entry_attrs(attrs) do
        entry
        |> FinanceEntry.changeset(normalized)
        |> persist_changeset()
      else
        nil -> {:error, :not_found}
        {:error, _reason} = error -> error
      end

    with {:ok, _entry} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
  end

  def delete_finance_entry(%Scope{} = scope, id) do
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           %FinanceEntry{} = entry <- Repo.get_by(FinanceEntry, id: id, user_id: user_id),
           {:ok, entry} <- Repo.delete(entry) do
        {:ok, entry}
      else
        nil -> {:error, :not_found}
        {:error, _reason} = error -> error
      end

    with {:ok, _entry} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
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

      days =
        parse_positive_integer_or_default(Map.get(params, "days") || Map.get(params, :days), 365)

      progress_min =
        parse_non_negative_integer_or_default(
          Map.get(params, "progress_min") || Map.get(params, :progress_min),
          0
        )

      progress_max =
        parse_non_negative_integer_or_default(
          Map.get(params, "progress_max") || Map.get(params, :progress_max),
          nil
        )

      query_text = Map.get(params, "q") || Map.get(params, :q) || ""

      with {:ok, status_filter} <-
             parse_enum_filter_value(status_filter, Goal.statuses(), :status),
           {:ok, horizon_filter} <-
             parse_enum_filter_value(horizon_filter, Goal.horizons(), :horizon) do
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

        # Filter by period (due_on)
        query =
          from g in query,
            where: is_nil(g.due_on) or g.due_on <= ^Date.add(Date.utc_today(), days)

        # Filter by text search
        safe_query = query_text |> String.trim() |> String.slice(0, 100)

        query =
          if safe_query != "" do
            search_pattern = "%#{safe_query}%"

            from g in query,
              where: ilike(g.title, ^search_pattern) or ilike(g.notes, ^search_pattern)
          else
            query
          end

        # Filter by progress range (defensively handle division by zero)
        query =
          if progress_min > 0 or is_integer(progress_max) do
            from g in query,
              where:
                fragment(
                  "CASE WHEN ? > 0 THEN CAST(? * 100.0 / ? AS INTEGER) ELSE 0 END >= ? AND (? IS NULL OR CAST(? * 100.0 / ? AS INTEGER) <= ?)",
                  g.target_value,
                  g.current_value,
                  g.target_value,
                  ^progress_min,
                  ^progress_max,
                  g.current_value,
                  g.target_value,
                  ^progress_max
                )
          else
            query
          end

        {:ok, Repo.all(query)}
      end
    end
  end

  def create_goal(%Scope{} = scope, attrs) when is_map(attrs) do
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           {:ok, normalized} <- AttributeValidation.validate_goal_attrs(attrs) do
        %Goal{user_id: user_id}
        |> Goal.changeset(normalized)
        |> persist_changeset()
      end

    with {:ok, _goal} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
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
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           %Goal{} = goal <- Repo.get_by(Goal, id: id, user_id: user_id),
           {:ok, normalized} <- AttributeValidation.validate_goal_attrs(attrs) do
        goal
        |> Goal.changeset(normalized)
        |> persist_changeset()
      else
        nil -> {:error, :not_found}
        {:error, _reason} = error -> error
      end

    with {:ok, _goal} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
  end

  def delete_goal(%Scope{} = scope, id) do
    result =
      with {:ok, user_id} <- scope_user_id(scope),
           %Goal{} = goal <- Repo.get_by(Goal, id: id, user_id: user_id),
           {:ok, goal} <- Repo.delete(goal) do
        {:ok, goal}
      else
        nil -> {:error, :not_found}
        {:error, _reason} = error -> error
      end

    with {:ok, _goal} <- result do
      Organizer.Planning.AnalyticsCache.invalidate_for_user(scope)
    end

    result
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
    with {:ok, user_id} <- scope_user_id(scope),
         {:ok, normalized} <- AttributeValidation.validate_important_date_attrs(attrs) do
      %ImportantDate{user_id: user_id}
      |> ImportantDate.changeset(normalized)
      |> persist_changeset()
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
         %ImportantDate{} = date <- Repo.get_by(ImportantDate, id: id, user_id: user_id),
         {:ok, normalized} <- AttributeValidation.validate_important_date_attrs(attrs) do
      date
      |> ImportantDate.changeset(normalized)
      |> persist_changeset()
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
    with {:ok, user_id} <- scope_user_id(scope),
         {:ok, normalized} <- AttributeValidation.validate_fixed_cost_attrs(attrs) do
      %FixedCost{user_id: user_id}
      |> FixedCost.changeset(normalized)
      |> persist_changeset()
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
         %FixedCost{} = cost <- Repo.get_by(FixedCost, id: id, user_id: user_id),
         {:ok, normalized} <- AttributeValidation.validate_fixed_cost_attrs(attrs) do
      cost
      |> FixedCost.changeset(normalized)
      |> persist_changeset()
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
    days = parse_positive_integer_or_default(read_option_value(opts, :days), 14)

    planned_capacity =
      parse_non_negative_integer_or_default(read_option_value(opts, :planned_capacity), 10)

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
    days = parse_positive_integer_or_default(read_option_value(opts, :days), 365)

    planned_capacity =
      parse_non_negative_integer_or_default(read_option_value(opts, :planned_capacity), 10)

    with {:ok, tasks} <- list_tasks(scope, %{days: days}) do
      {:ok,
       %{
         progress_by_period: Analytics.progress_by_period(tasks),
         workload_capacity: Analytics.workload_capacity_snapshot(tasks, planned_capacity),
         burnout_risk_assessment: Analytics.burnout_risk_assessment(tasks)
       }}
    end
  end

  defp merge_task_defaults(%Task{} = task, attrs) do
    defaults = %{
      "title" => task.title,
      "notes" => task.notes,
      "status" => Atom.to_string(task.status),
      "priority" => Atom.to_string(task.priority),
      "due_on" => task.due_on
    }

    Map.merge(defaults, normalize_string_keys(attrs))
  end

  defp create_task_checklist_item(task, label) do
    next_position = next_task_checklist_item_position(task.id)

    %TaskChecklistItem{task_id: task.id}
    |> TaskChecklistItem.changeset(%{
      label: label,
      position: next_position,
      checked: false,
      checked_at: nil
    })
    |> persist_changeset()
  end

  defp update_checklist_item_checked(item, checked?) do
    checked_at = if checked?, do: DateTime.utc_now() |> DateTime.truncate(:second), else: nil

    item
    |> TaskChecklistItem.changeset(%{
      checked: checked?,
      checked_at: checked_at
    })
    |> persist_changeset()
  end

  defp sync_task_status_with_checklist(scope, task_id) do
    with {:ok, task} <- get_task(scope, task_id) do
      checklist_items = task.checklist_items
      total = length(checklist_items)
      checked_total = Enum.count(checklist_items, & &1.checked)

      desired_status =
        cond do
          total == 0 -> task.status
          checked_total == total -> :done
          checked_total > 0 -> :in_progress
          true -> :todo
        end

      if desired_status == task.status do
        {:ok, task}
      else
        completed_at =
          if desired_status == :done, do: DateTime.utc_now() |> DateTime.truncate(:second)

        task
        |> Task.changeset(%{
          title: task.title,
          notes: task.notes,
          due_on: task.due_on,
          priority: task.priority,
          status: desired_status,
          completed_at: completed_at
        })
        |> persist_changeset()
      end
    end
  end

  defp task_with_checklist_items_query(user_id, id) do
    checklist_query =
      from i in TaskChecklistItem,
        order_by: [asc: i.position, asc: i.inserted_at]

    from t in Task,
      where: t.id == ^id and t.user_id == ^user_id,
      preload: [checklist_items: ^checklist_query]
  end

  defp next_task_checklist_item_position(task_id) do
    (Repo.one(
       from i in TaskChecklistItem,
         where: i.task_id == ^task_id,
         select: max(i.position)
     ) || -1) + 1
  end

  defp validate_checklist_label(attrs) do
    label =
      attrs
      |> Map.get("label", Map.get(attrs, :label))
      |> to_string()
      |> String.trim()

    cond do
      label == "" ->
        {:error, {:validation, %{label: ["is required"]}}}

      String.length(label) > 140 ->
        {:error, {:validation, %{label: ["is too long"]}}}

      true ->
        {:ok, label}
    end
  end

  defp parse_checked_flag(value) when value in [true, "true", "1", 1, "on"], do: {:ok, true}
  defp parse_checked_flag(value) when value in [false, "false", "0", 0, "off"], do: {:ok, false}
  defp parse_checked_flag(_value), do: {:error, {:validation, %{checked: ["is invalid"]}}}

  defp normalize_string_keys(attrs) do
    Enum.into(attrs, %{}, fn {k, v} -> {to_string(k), v} end)
  end

  defp persist_changeset(changeset) do
    case Repo.insert_or_update(changeset) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> {:error, {:validation, build_changeset_error_map(changeset)}}
    end
  end

  defp build_changeset_error_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", error_option_value_to_string(value))
      end)
    end)
  end

  defp error_option_value_to_string(value) when is_binary(value), do: value
  defp error_option_value_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp error_option_value_to_string(value) when is_float(value), do: Float.to_string(value)
  defp error_option_value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp error_option_value_to_string(value), do: inspect(value)

  defp scope_user_id(%Scope{user: %{id: user_id}}), do: {:ok, user_id}
  defp scope_user_id(_), do: {:error, :unauthorized}

  defp parse_positive_integer_or_default(nil, default), do: default
  defp parse_positive_integer_or_default("", default), do: default

  defp parse_positive_integer_or_default(value, _default) when is_integer(value) and value > 0,
    do: value

  defp parse_positive_integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp parse_positive_integer_or_default(_, default), do: default

  defp parse_non_negative_integer_or_default(nil, default), do: default
  defp parse_non_negative_integer_or_default("", default), do: default

  defp parse_non_negative_integer_or_default(value, _default)
       when is_integer(value) and value >= 0,
       do: value

  defp parse_non_negative_integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> default
    end
  end

  defp parse_non_negative_integer_or_default(_, default), do: default

  defp read_option_value(opts, key) when is_map(opts),
    do: Map.get(opts, key) || Map.get(opts, Atom.to_string(key))

  defp read_option_value(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp read_option_value(_opts, _key), do: nil

  defp parse_enum_filter_value(value, allowed_atoms, field) do
    # Use the new FilterNormalization module with typo tolerance
    FilterNormalization.normalize_filter_value(value, allowed_atoms, field)
  end
end
