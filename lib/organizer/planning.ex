defmodule Organizer.Planning do
  @moduledoc """
  Context for day-to-day planning domains: tasks, finance and schedule.
  """

  import Ecto.Query, warn: false
  alias Organizer.Accounts.User
  alias Organizer.Accounts.Scope
  alias Organizer.Planning.Analytics
  alias Organizer.Planning.AttributeValidation
  alias Organizer.Planning.FilterNormalization
  alias Organizer.Planning.FinanceEntry
  alias Organizer.Planning.FixedCost
  alias Organizer.Planning.ImportantDate
  alias Organizer.Planning.Task
  alias Organizer.Planning.TaskChecklistItem
  alias Organizer.SharedFinance.AccountLink
  alias Organizer.DateSupport
  alias Organizer.SharedFinance
  alias Organizer.Repo

  def list_tasks(%Scope{} = scope, params \\ %{}) do
    with {:ok, user_id} <- scope_user_id(scope) do
      status_filter = Map.get(params, "status") || Map.get(params, :status)
      priority_filter = Map.get(params, "priority") || Map.get(params, :priority)

      days =
        parse_positive_integer_or_default(Map.get(params, "days") || Map.get(params, :days), 7)

      query_text = Map.get(params, "q") || Map.get(params, :q) || ""

      pagination_limit =
        parse_positive_integer_or_default(
          Map.get(params, "limit") || Map.get(params, :limit),
          nil
        )

      pagination_offset =
        parse_non_negative_integer_or_default(
          Map.get(params, "offset") || Map.get(params, :offset),
          0
        )

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

        query =
          maybe_paginate_task_query(query, pagination_limit, pagination_offset)

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

    with {:ok, updated_task} <- result do
      synced_user_ids = sync_task_pair_status(updated_task)
      invalidate_analytics_for_user_ids([scope.user.id | synced_user_ids])
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

  def share_task_with_link(%Scope{} = scope, task_id, link_id, attrs \\ %{}) do
    share_mode = parse_task_share_mode(attrs)

    result =
      with {:ok, user_id} <- scope_user_id(scope),
           {:ok, normalized_link_id} <- parse_positive_id(link_id),
           %Task{} = source_task <-
             task_with_checklist_items_query(user_id, task_id) |> Repo.one(),
           :ok <- validate_sync_share_availability(source_task, share_mode),
           {:ok, link} <- SharedFinance.get_account_link(scope, normalized_link_id),
           {:ok, recipient_user_id} <- linked_partner_user_id(link, user_id),
           {:ok, shared_task} <-
             duplicate_task_for_partner(
               source_task,
               recipient_user_id,
               normalized_link_id,
               share_mode,
               scope
             ) do
        {:ok, shared_task, recipient_user_id}
      else
        nil ->
          {:error, :not_found}

        :error ->
          {:error, :not_found}

        {:error, :invalid_id} ->
          {:error, {:validation, %{link_id: ["is invalid"]}}}

        {:error, :already_synchronized} ->
          {:error, {:validation, %{mode: ["task already has an active sync link"]}}}

        {:error, _reason} = error ->
          error
      end

    with {:ok, _shared_task, recipient_user_id} <- result do
      invalidate_analytics_for_user_ids([scope.user.id, recipient_user_id])
    end

    case result do
      {:ok, shared_task, _recipient_user_id} -> {:ok, shared_task}
      error -> error
    end
  end

  def add_task_checklist_item(%Scope{} = scope, task_id, attrs) when is_map(attrs) do
    with {:ok, user_id} <- scope_user_id(scope),
         %Task{} = task <- Repo.get_by(Task, id: task_id, user_id: user_id),
         {:ok, label} <- validate_checklist_label(attrs),
         {:ok, item} <- create_task_checklist_item(task, label),
         {:ok, _task} <- sync_task_status_with_checklist(scope, task.id) do
      synced_user_ids = sync_task_pair_status_and_checklist(task.id)
      invalidate_analytics_for_user_ids([scope.user.id | synced_user_ids])
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
      synced_user_ids = sync_task_pair_status_and_checklist(task.id)
      invalidate_analytics_for_user_ids([scope.user.id | synced_user_ids])
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
      synced_user_ids = sync_task_pair_status_and_checklist(task.id)
      invalidate_analytics_for_user_ids([scope.user.id | synced_user_ids])
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
      synced_user_ids = sync_task_pair_status_and_checklist(task.id)
      invalidate_analytics_for_user_ids([scope.user.id | synced_user_ids])
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

      kind_filter = Map.get(params, "kind") || Map.get(params, :kind)

      expense_profile_filter =
        Map.get(params, "expense_profile") || Map.get(params, :expense_profile)

      payment_method_filter =
        Map.get(params, "payment_method") || Map.get(params, :payment_method)

      period_mode =
        parse_finance_period_mode(Map.get(params, "period_mode") || Map.get(params, :period_mode))

      month_filter = Map.get(params, "month") || Map.get(params, :month)

      specific_date_filter =
        parse_optional_date_filter(
          Map.get(params, "occurred_on") || Map.get(params, :occurred_on)
        )

      from_date_filter =
        parse_optional_date_filter(
          Map.get(params, "occurred_from") || Map.get(params, :occurred_from)
        )

      to_date_filter =
        parse_optional_date_filter(
          Map.get(params, "occurred_to") || Map.get(params, :occurred_to)
        )

      weekday_filter =
        parse_weekday_filter(Map.get(params, "weekday") || Map.get(params, :weekday))

      category_filter = Map.get(params, "category") || Map.get(params, :category) || ""
      query_text = Map.get(params, "q") || Map.get(params, :q) || ""
      sort_by = parse_finance_sort_by(Map.get(params, "sort_by") || Map.get(params, :sort_by))

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

      pagination_limit =
        parse_positive_integer_or_default(
          Map.get(params, "limit") || Map.get(params, :limit),
          nil
        )

      pagination_offset =
        parse_non_negative_integer_or_default(
          Map.get(params, "offset") || Map.get(params, :offset),
          0
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
            where: f.user_id == ^user_id

        query =
          apply_finance_period_filter(
            query,
            period_mode,
            days,
            month_filter,
            specific_date_filter,
            from_date_filter,
            to_date_filter,
            weekday_filter
          )

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

        safe_query = sanitize_filter_query(query_text)

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

        query =
          query
          |> apply_finance_sorting(sort_by)
          |> maybe_paginate_finance_query(pagination_limit, pagination_offset)

        {:ok, Repo.all(query)}
      end
    end
  end

  def list_finance_category_suggestions(%Scope{} = scope) do
    with {:ok, user_id} <- scope_user_id(scope) do
      linked_user_ids = linked_user_ids_for_scope(user_id)
      user_ids = ([user_id] ++ linked_user_ids) |> Enum.uniq()

      query =
        from f in FinanceEntry,
          where: f.user_id in ^user_ids and not is_nil(f.category),
          select: {f.kind, f.category}

      suggestions =
        query
        |> Repo.all()
        |> Enum.reduce(%{income: [], expense: []}, fn {kind, category}, acc ->
          cleaned = String.trim(category || "")

          cond do
            cleaned == "" ->
              acc

            kind == :income ->
              Map.update!(acc, :income, &[cleaned | &1])

            kind == :expense ->
              Map.update!(acc, :expense, &[cleaned | &1])

            true ->
              acc
          end
        end)
        |> normalize_category_suggestion_map()

      {:ok, suggestions}
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

  defp duplicate_task_for_partner(
         source_task,
         recipient_user_id,
         link_id,
         share_mode,
         scope
       ) do
    pair_uuid = Ecto.UUID.generate()
    sync_mode = if share_mode == :sync, do: :sync, else: :copy

    task_attrs =
      source_task
      |> build_shared_task_attrs(scope, share_mode)
      |> Map.put(:shared_pair_uuid, pair_uuid)
      |> Map.put(:shared_origin_task_id, source_task.id)
      |> Map.put(:shared_sync_mode, sync_mode)
      |> Map.put(:shared_with_link_id, link_id)

    Repo.transaction(fn ->
      with {:ok, shared_task} <-
             %Task{user_id: recipient_user_id}
             |> Task.changeset(task_attrs)
             |> Ecto.Changeset.put_change(:shared_pair_uuid, pair_uuid)
             |> Ecto.Changeset.put_change(:shared_origin_task_id, source_task.id)
             |> Ecto.Changeset.put_change(:shared_sync_mode, sync_mode)
             |> Ecto.Changeset.put_change(:shared_with_link_id, link_id)
             |> persist_changeset(),
           {:ok, _shared_items} <-
             copy_task_checklist_for_shared_task(
               Map.get(source_task, :checklist_items, []),
               shared_task.id,
               share_mode
             ),
           {:ok, _source_task} <-
             maybe_mark_source_task_as_sync_source(source_task, pair_uuid, link_id, share_mode) do
        shared_task
      else
        {:error, _reason} = error -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, shared_task} ->
        {:ok, shared_task}

      {:error, {:validation, _details} = error} ->
        error

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_shared_task_attrs(source_task, scope, :sync) do
    %{
      title: source_task.title,
      notes: shared_task_notes(scope, source_task.notes),
      due_on: source_task.due_on,
      priority: source_task.priority,
      status: source_task.status,
      completed_at: source_task.completed_at
    }
  end

  defp build_shared_task_attrs(source_task, scope, _share_mode) do
    %{
      title: source_task.title,
      notes: shared_task_notes(scope, source_task.notes),
      due_on: source_task.due_on,
      priority: source_task.priority,
      status: :todo,
      completed_at: nil
    }
  end

  defp copy_task_checklist_for_shared_task(checklist_items, shared_task_id, :sync) do
    checklist_items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, inserted_items} ->
      case %TaskChecklistItem{task_id: shared_task_id}
           |> TaskChecklistItem.changeset(%{
             label: item.label,
             position: index,
             checked: item.checked,
             checked_at: item.checked_at
           })
           |> persist_changeset() do
        {:ok, inserted_item} ->
          {:cont, {:ok, [inserted_item | inserted_items]}}

        {:error, {:validation, _details} = error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, inserted_items} -> {:ok, Enum.reverse(inserted_items)}
      {:error, {:validation, _details} = error} -> {:error, error}
    end
  end

  defp copy_task_checklist_for_shared_task(checklist_items, shared_task_id, _share_mode) do
    checklist_items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, inserted_items} ->
      case %TaskChecklistItem{task_id: shared_task_id}
           |> TaskChecklistItem.changeset(%{
             label: item.label,
             position: index,
             checked: false,
             checked_at: nil
           })
           |> persist_changeset() do
        {:ok, inserted_item} ->
          {:cont, {:ok, [inserted_item | inserted_items]}}

        {:error, {:validation, _details} = error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, inserted_items} -> {:ok, Enum.reverse(inserted_items)}
      {:error, {:validation, _details} = error} -> {:error, error}
    end
  end

  defp maybe_mark_source_task_as_sync_source(source_task, pair_uuid, link_id, :sync) do
    source_task
    |> Ecto.Changeset.change(%{
      shared_pair_uuid: pair_uuid,
      shared_origin_task_id: nil,
      shared_sync_mode: :sync,
      shared_with_link_id: link_id
    })
    |> persist_changeset()
  end

  defp maybe_mark_source_task_as_sync_source(_source_task, _pair_uuid, _link_id, _share_mode),
    do: {:ok, :not_synced}

  defp linked_partner_user_id(link, owner_user_id) do
    cond do
      owner_user_id == link.user_a_id -> {:ok, link.user_b_id}
      owner_user_id == link.user_b_id -> {:ok, link.user_a_id}
      true -> :error
    end
  end

  defp shared_task_notes(scope, notes) do
    owner_label =
      case scope do
        %Scope{user: %{email: email}} when is_binary(email) and email != "" -> email
        _ -> "conta vinculada"
      end

    prefix = "Compartilhada por #{owner_label} em #{Date.to_iso8601(Date.utc_today())}."

    notes =
      case notes do
        value when is_binary(value) and value != "" ->
          prefix <> "\n\n" <> String.trim(value)

        _ ->
          prefix
      end

    String.slice(notes, 0, 1000)
  end

  defp validate_sync_share_availability(source_task, :sync) do
    if is_binary(source_task.shared_pair_uuid) and source_task.shared_pair_uuid != "" and
         source_task.shared_sync_mode == :sync do
      {:error, :already_synchronized}
    else
      :ok
    end
  end

  defp validate_sync_share_availability(_source_task, _share_mode), do: :ok

  defp sync_task_pair_status(%Task{} = source_task) do
    with :sync <- source_task.shared_sync_mode,
         true <- is_binary(source_task.shared_pair_uuid),
         true <- is_integer(source_task.shared_with_link_id),
         {:ok, counterpart} <- get_sync_counterpart_task(source_task),
         {:ok, updated_counterpart} <- mirror_task_status(source_task, counterpart) do
      [updated_counterpart.user_id]
    else
      _ -> []
    end
  end

  defp sync_task_pair_status_and_checklist(task_id) do
    with %Task{} = source_task <- task_with_checklist_by_id(task_id),
         :sync <- source_task.shared_sync_mode,
         true <- is_binary(source_task.shared_pair_uuid),
         true <- is_integer(source_task.shared_with_link_id),
         {:ok, counterpart} <- get_sync_counterpart_task(source_task),
         {:ok, updated_counterpart} <- mirror_task_status_and_checklist(source_task, counterpart) do
      [updated_counterpart.user_id]
    else
      _ -> []
    end
  end

  defp task_with_checklist_by_id(task_id) do
    checklist_query =
      from i in TaskChecklistItem,
        order_by: [asc: i.position, asc: i.inserted_at]

    from(t in Task,
      where: t.id == ^task_id,
      preload: [checklist_items: ^checklist_query]
    )
    |> Repo.one()
  end

  defp get_sync_counterpart_task(source_task) do
    checklist_query =
      from i in TaskChecklistItem,
        order_by: [asc: i.position, asc: i.inserted_at]

    query =
      from t in Task,
        where:
          t.id != ^source_task.id and
            t.shared_pair_uuid == ^source_task.shared_pair_uuid and
            t.shared_with_link_id == ^source_task.shared_with_link_id and
            t.shared_sync_mode == :sync,
        preload: [checklist_items: ^checklist_query]

    case Repo.one(query) do
      %Task{} = counterpart -> {:ok, counterpart}
      _ -> :error
    end
  end

  defp mirror_task_status(source_task, counterpart) do
    completed_at =
      if source_task.status == :done,
        do: source_task.completed_at || DateTime.utc_now() |> DateTime.truncate(:second),
        else: nil

    counterpart
    |> Ecto.Changeset.change(%{
      status: source_task.status,
      completed_at: completed_at
    })
    |> persist_changeset()
  end

  defp mirror_task_status_and_checklist(source_task, counterpart) do
    Repo.transaction(fn ->
      with {:ok, updated_counterpart} <- mirror_task_status(source_task, counterpart),
           {_, _deleted} <-
             Repo.delete_all(from i in TaskChecklistItem, where: i.task_id == ^counterpart.id),
           {:ok, _inserted_items} <-
             copy_task_checklist_for_shared_task(
               Map.get(source_task, :checklist_items, []),
               counterpart.id,
               :sync
             ) do
        updated_counterpart
      else
        {:error, _reason} = error -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, updated_counterpart} -> {:ok, updated_counterpart}
      {:error, {:validation, _details} = error} -> error
      {:error, _reason} = error -> error
    end
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

  defp parse_task_share_mode(attrs) when is_map(attrs) do
    attrs
    |> Map.get("mode", Map.get(attrs, :mode, "copy"))
    |> to_string()
    |> String.trim()
    |> case do
      "sync" -> :sync
      _ -> :copy
    end
  end

  defp parse_task_share_mode(_attrs), do: :copy

  defp invalidate_analytics_for_user_ids(user_ids) do
    user_ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(fn user_id ->
      Organizer.Planning.AnalyticsCache.invalidate_for_user(%Scope{user: %User{id: user_id}})
    end)
  end

  defp parse_positive_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> Integer.parse()
    |> case do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_positive_id(_value), do: {:error, :invalid_id}

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

  defp parse_optional_date_filter(nil), do: nil
  defp parse_optional_date_filter(""), do: nil

  defp parse_optional_date_filter(value) do
    case DateSupport.parse_date(value) do
      {:ok, date} -> date
      :error -> nil
    end
  end

  defp parse_finance_period_mode(value) do
    case normalize_filter_string(value) do
      "specific_date" -> :specific_date
      "month" -> :month
      "range" -> :range
      "weekday" -> :weekday
      _ -> :rolling
    end
  end

  defp parse_finance_sort_by(value) do
    case normalize_filter_string(value) do
      "date_asc" -> :date_asc
      "amount_desc" -> :amount_desc
      "amount_asc" -> :amount_asc
      "category_asc" -> :category_asc
      _ -> :date_desc
    end
  end

  defp parse_weekday_filter(value) when is_integer(value) and value >= 0 and value <= 6,
    do: value

  defp parse_weekday_filter(value) when is_binary(value) do
    case normalize_filter_string(value) do
      "" ->
        nil

      "all" ->
        nil

      normalized ->
        case Integer.parse(normalized) do
          {weekday, ""} when weekday >= 0 and weekday <= 6 -> weekday
          _ -> nil
        end
    end
  end

  defp parse_weekday_filter(_value), do: nil

  defp apply_finance_period_filter(
         query,
         :specific_date,
         _days,
         _month_filter,
         %Date{} = specific_date,
         _from_date,
         _to_date,
         _weekday
       ) do
    from f in query, where: f.occurred_on == ^specific_date
  end

  defp apply_finance_period_filter(
         query,
         :month,
         days,
         month_filter,
         _specific_date,
         _from_date,
         _to_date,
         _weekday
       ) do
    case month_filter |> normalize_filter_string() |> DateSupport.parse_month_year() do
      {:ok, {start_on, end_on}} ->
        from f in query, where: f.occurred_on >= ^start_on and f.occurred_on <= ^end_on

      :error ->
        apply_finance_period_filter(query, :rolling, days, nil, nil, nil, nil, nil)
    end
  end

  defp apply_finance_period_filter(
         query,
         :range,
         _days,
         _month_filter,
         _specific_date,
         from_date,
         to_date,
         _weekday
       ) do
    query
    |> maybe_filter_from_date(from_date)
    |> maybe_filter_to_date(to_date)
  end

  defp apply_finance_period_filter(
         query,
         :weekday,
         _days,
         _month_filter,
         _specific_date,
         _from_date,
         _to_date,
         weekday
       )
       when is_integer(weekday) do
    weekday_string = Integer.to_string(weekday)
    from f in query, where: fragment("strftime('%w', ?)", f.occurred_on) == ^weekday_string
  end

  defp apply_finance_period_filter(
         query,
         _period_mode,
         days,
         _month_filter,
         _specific_date,
         _from_date,
         _to_date,
         _weekday
       ) do
    start_on = Date.add(Date.utc_today(), -days)
    from f in query, where: f.occurred_on >= ^start_on
  end

  defp maybe_filter_from_date(query, %Date{} = from_date) do
    from f in query, where: f.occurred_on >= ^from_date
  end

  defp maybe_filter_from_date(query, _from_date), do: query

  defp maybe_filter_to_date(query, %Date{} = to_date) do
    from f in query, where: f.occurred_on <= ^to_date
  end

  defp maybe_filter_to_date(query, _to_date), do: query

  defp apply_finance_sorting(query, :date_asc) do
    from f in query, order_by: [asc: f.occurred_on, asc: f.inserted_at]
  end

  defp apply_finance_sorting(query, :amount_desc) do
    from f in query, order_by: [desc: f.amount_cents, desc: f.occurred_on, desc: f.inserted_at]
  end

  defp apply_finance_sorting(query, :amount_asc) do
    from f in query, order_by: [asc: f.amount_cents, desc: f.occurred_on, desc: f.inserted_at]
  end

  defp apply_finance_sorting(query, :category_asc) do
    from f in query, order_by: [asc: f.category, desc: f.occurred_on, desc: f.inserted_at]
  end

  defp apply_finance_sorting(query, _sort_by) do
    from f in query, order_by: [desc: f.occurred_on, desc: f.inserted_at]
  end

  defp maybe_paginate_task_query(query, nil, _offset), do: query

  defp maybe_paginate_task_query(query, limit, offset)
       when is_integer(limit) and is_integer(offset) do
    from t in query, limit: ^limit, offset: ^offset
  end

  defp maybe_paginate_finance_query(query, nil, _offset), do: query

  defp maybe_paginate_finance_query(query, limit, offset)
       when is_integer(limit) and is_integer(offset) do
    from f in query, limit: ^limit, offset: ^offset
  end

  defp sanitize_filter_query(query_text) when is_binary(query_text) do
    query_text
    |> String.trim()
    |> String.slice(0, 100)
  end

  defp sanitize_filter_query(_query_text), do: ""

  defp linked_user_ids_for_scope(user_id) do
    query =
      from l in AccountLink,
        where:
          l.status == :active and
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id),
        select:
          fragment(
            "CASE WHEN ? = ? THEN ? ELSE ? END",
            l.user_a_id,
            ^user_id,
            l.user_b_id,
            l.user_a_id
          )

    query
    |> Repo.all()
    |> Enum.filter(&is_integer/1)
  end

  defp normalize_category_suggestion_map(%{income: income, expense: expense}) do
    normalized_income = normalize_category_list(income)
    normalized_expense = normalize_category_list(expense)

    %{
      income: normalized_income,
      expense: normalized_expense,
      all: normalize_category_list(normalized_income ++ normalized_expense)
    }
  end

  defp normalize_category_list(categories) when is_list(categories) do
    categories
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.sort_by(&String.downcase/1)
  end

  defp normalize_filter_string(value) when is_binary(value), do: String.trim(value)

  defp normalize_filter_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.trim()

  defp normalize_filter_string(value) when is_integer(value),
    do: value |> Integer.to_string() |> String.trim()

  defp normalize_filter_string(_value), do: ""

  defp read_option_value(opts, key) when is_map(opts),
    do: Map.get(opts, key) || Map.get(opts, Atom.to_string(key))

  defp read_option_value(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp read_option_value(_opts, _key), do: nil

  defp parse_enum_filter_value(value, allowed_atoms, field) do
    # Use the new FilterNormalization module with typo tolerance
    FilterNormalization.normalize_filter_value(value, allowed_atoms, field)
  end
end
