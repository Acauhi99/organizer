defmodule Organizer.Planning do
  @moduledoc """
  Context for personal finance and supporting planning domains.
  """

  import Ecto.Query, warn: false

  alias Organizer.Accounts.Scope
  alias Organizer.DateSupport
  alias Organizer.Planning.AttributeValidation
  alias Organizer.Planning.FilterNormalization
  alias Organizer.Planning.FinanceEntry
  alias Organizer.Planning.FixedCost
  alias Organizer.Planning.ImportantDate
  alias Organizer.Repo
  alias Organizer.SharedFinance
  alias Organizer.SharedFinance.AccountLink

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
      SharedFinance.rebalance_user_links(scope)
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
      SharedFinance.rebalance_user_links(scope)
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
      SharedFinance.rebalance_user_links(scope)
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

  defp parse_enum_filter_value(value, allowed_atoms, field) do
    FilterNormalization.normalize_filter_value(value, allowed_atoms, field)
  end
end
