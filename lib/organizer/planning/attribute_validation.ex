defmodule Organizer.Planning.AttributeValidation do
  @moduledoc """
  Validation and normalization rules for planning attributes.
  """

  alias Organizer.DateSupport

  @task_statuses ~w(todo in_progress done)
  @task_priorities ~w(low medium high)
  @finance_kinds ~w(income expense)
  @finance_expense_profiles ~w(fixed variable recurring_fixed recurring_variable)
  @finance_payment_methods ~w(credit debit)
  @important_date_categories ~w(personal finance work)
  @max_installments_count 120

  def validate_task_attrs(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    {title, errors} = validate_required_string(attrs, :title, 3, 120, %{})
    {notes, errors} = validate_optional_string(attrs, :notes, 1_000, errors)
    {status, errors} = validate_enum(attrs, :status, @task_statuses, "todo", errors)
    {priority, errors} = validate_enum(attrs, :priority, @task_priorities, "medium", errors)
    {due_on, errors} = validate_optional_date(attrs, :due_on, errors)

    build_result(errors, %{
      title: title,
      notes: notes,
      status: String.to_existing_atom(status),
      priority: String.to_existing_atom(priority),
      due_on: due_on,
      completed_at: completed_at_for(status)
    })
  end

  def validate_finance_entry_attrs(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    {kind, errors} = validate_enum(attrs, :kind, @finance_kinds, nil, %{})

    {expense_profile, payment_method, installment_number, installments_count, errors} =
      validate_expense_classification_attrs(attrs, kind, errors)

    {amount_cents, errors} = validate_positive_int(attrs, :amount_cents, errors)
    {category, errors} = validate_required_string(attrs, :category, 2, 80, errors)
    {description, errors} = validate_optional_string(attrs, :description, 300, errors)

    {occurred_on, errors} =
      validate_date_with_default(attrs, :occurred_on, Date.utc_today(), errors)

    build_result(errors, %{
      kind: safe_existing_atom(kind),
      expense_profile: safe_existing_atom(expense_profile),
      payment_method: safe_existing_atom(payment_method),
      installment_number: installment_number,
      installments_count: installments_count,
      amount_cents: amount_cents,
      category: category,
      description: description,
      occurred_on: occurred_on
    })
  end

  def validate_important_date_attrs(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    {title, errors} = validate_required_string(attrs, :title, 2, 100, %{})

    {category, errors} =
      validate_enum(attrs, :category, @important_date_categories, "personal", errors)

    {date, errors} = validate_required_date(attrs, :date, errors)
    {notes, errors} = validate_optional_string(attrs, :notes, 300, errors)

    build_result(errors, %{
      title: title,
      category: String.to_atom(category),
      date: date,
      notes: notes
    })
  end

  def validate_fixed_cost_attrs(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    {name, errors} = validate_required_string(attrs, :name, 2, 80, %{})
    {amount_cents, errors} = validate_positive_int(attrs, :amount_cents, errors)
    {billing_day, errors} = validate_billing_day(attrs, :billing_day, errors)
    {starts_on, errors} = validate_optional_date(attrs, :starts_on, errors)
    {active, errors} = validate_optional_boolean(attrs, :active, true, errors)

    build_result(errors, %{
      name: name,
      amount_cents: amount_cents,
      billing_day: billing_day,
      starts_on: starts_on,
      active: active
    })
  end

  defp normalize_keys(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      case normalize_key(key) do
        nil -> acc
        map_key -> Map.put(acc, map_key, value)
      end
    end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> nil
    end
  end

  defp normalize_key(_), do: nil

  defp validate_required_string(attrs, field, min, max, errors) do
    case Map.get(attrs, field) do
      value when is_binary(value) ->
        cleaned = String.trim(value)

        cond do
          cleaned == "" -> {nil, add_error(errors, field, "is required")}
          String.length(cleaned) < min -> {cleaned, add_error(errors, field, "is too short")}
          String.length(cleaned) > max -> {cleaned, add_error(errors, field, "is too long")}
          true -> {cleaned, errors}
        end

      _ ->
        {nil, add_error(errors, field, "is required")}
    end
  end

  defp validate_optional_string(attrs, field, max, errors) do
    case Map.get(attrs, field) do
      nil ->
        {nil, errors}

      "" ->
        {nil, errors}

      value when is_binary(value) ->
        cleaned = String.trim(value)

        if String.length(cleaned) > max do
          {cleaned, add_error(errors, field, "is too long")}
        else
          {cleaned, errors}
        end

      _ ->
        {nil, add_error(errors, field, "must be a string")}
    end
  end

  defp validate_enum(attrs, field, allowed, default, errors) do
    case Map.get(attrs, field, default) do
      nil ->
        {nil, add_error(errors, field, "is required")}

      value when is_atom(value) ->
        string_value = Atom.to_string(value)
        validate_enum_value(string_value, field, allowed, errors)

      value when is_binary(value) ->
        cleaned = String.trim(value)
        validate_enum_value(cleaned, field, allowed, errors)

      _ ->
        {default, add_error(errors, field, "is invalid")}
    end
  end

  defp validate_enum_value(value, field, allowed, errors) do
    if value in allowed do
      {value, errors}
    else
      {value, add_error(errors, field, "is invalid")}
    end
  end

  defp validate_optional_enum(attrs, field, allowed, errors) do
    case Map.get(attrs, field) do
      nil ->
        {nil, errors}

      "" ->
        {nil, errors}

      value when is_atom(value) ->
        value
        |> Atom.to_string()
        |> validate_optional_enum_value(field, allowed, errors)

      value when is_binary(value) ->
        value
        |> String.trim()
        |> validate_optional_enum_value(field, allowed, errors)

      _ ->
        {nil, add_error(errors, field, "is invalid")}
    end
  end

  defp validate_optional_enum_value(value, _field, _allowed, errors) when value == "",
    do: {nil, errors}

  defp validate_optional_enum_value(value, field, allowed, errors) do
    if value in allowed do
      {value, errors}
    else
      {nil, add_error(errors, field, "is invalid")}
    end
  end

  defp validate_expense_classification_attrs(attrs, "expense", errors) do
    {expense_profile, errors} =
      validate_optional_enum(attrs, :expense_profile, @finance_expense_profiles, errors)

    {payment_method, errors} =
      validate_optional_enum(attrs, :payment_method, @finance_payment_methods, errors)

    {installment_number, errors} =
      validate_optional_positive_int(attrs, :installment_number, @max_installments_count, errors)

    {installments_count, errors} =
      validate_optional_positive_int(attrs, :installments_count, @max_installments_count, errors)

    normalized_payment_method = payment_method || "debit"

    {normalized_installment_number, normalized_installments_count} =
      if normalized_payment_method == "credit" do
        {installment_number || 1, installments_count || 1}
      else
        {nil, nil}
      end

    errors =
      if is_integer(normalized_installment_number) and is_integer(normalized_installments_count) and
           normalized_installment_number > normalized_installments_count do
        add_error(
          errors,
          :installment_number,
          "must be less than or equal to installments_count"
        )
      else
        errors
      end

    {expense_profile || "variable", normalized_payment_method, normalized_installment_number,
     normalized_installments_count, errors}
  end

  defp validate_expense_classification_attrs(_attrs, _kind, errors),
    do: {nil, nil, nil, nil, errors}

  defp validate_optional_date(attrs, field, errors) do
    case Map.get(attrs, field) do
      nil -> {nil, errors}
      "" -> {nil, errors}
      %Date{} = date -> {date, errors}
      value when is_binary(value) -> parse_date(value, field, errors)
      _ -> {nil, add_error(errors, field, "must be a valid date")}
    end
  end

  defp validate_date_with_default(attrs, field, default, errors) do
    case Map.get(attrs, field) do
      nil -> {default, errors}
      "" -> {default, errors}
      %Date{} = date -> {date, errors}
      value when is_binary(value) -> parse_date(value, field, errors)
      _ -> {default, add_error(errors, field, "must be a valid date")}
    end
  end

  defp validate_required_date(attrs, field, errors) do
    case Map.get(attrs, field) do
      nil -> {nil, add_error(errors, field, "is required")}
      "" -> {nil, add_error(errors, field, "is required")}
      %Date{} = date -> {date, errors}
      value when is_binary(value) -> parse_date(value, field, errors)
      _ -> {nil, add_error(errors, field, "must be a valid date")}
    end
  end

  defp parse_date(value, field, errors) do
    value
    |> DateSupport.parse_date()
    |> case do
      {:ok, parsed} ->
        {parsed, errors}

      :error ->
        {nil, add_error(errors, field, "must be in DD/MM/YYYY or YYYY-MM-DD format")}
    end
  end

  defp validate_positive_int(attrs, field, errors) do
    case parse_int(Map.get(attrs, field)) do
      {:ok, number} when number > 0 and number <= 1_000_000_000 ->
        {number, errors}

      {:ok, number} when number > 1_000_000_000 ->
        {nil, add_error(errors, field, "must be less than or equal to 1000000000")}

      {:ok, _number} ->
        {nil, add_error(errors, field, "must be greater than zero")}

      :error ->
        {nil, add_error(errors, field, "must be an integer")}
    end
  end

  defp validate_billing_day(attrs, field, errors) do
    case parse_int(Map.get(attrs, field)) do
      {:ok, number} when number >= 1 and number <= 31 -> {number, errors}
      {:ok, _number} -> {nil, add_error(errors, field, "must be between 1 and 31")}
      :error -> {nil, add_error(errors, field, "must be an integer")}
    end
  end

  defp validate_optional_positive_int(attrs, field, max, errors) do
    case Map.get(attrs, field) do
      nil ->
        {nil, errors}

      "" ->
        {nil, errors}

      value ->
        case parse_int(value) do
          {:ok, number} when number > 0 and number <= max ->
            {number, errors}

          {:ok, number} when number > max ->
            {nil, add_error(errors, field, "must be less than or equal to #{max}")}

          {:ok, _number} ->
            {nil, add_error(errors, field, "must be greater than zero")}

          :error ->
            {nil, add_error(errors, field, "must be an integer")}
        end
    end
  end

  defp validate_optional_boolean(attrs, field, default, errors) do
    case Map.get(attrs, field) do
      nil -> {default, errors}
      "" -> {default, errors}
      value when is_boolean(value) -> {value, errors}
      "true" -> {true, errors}
      "false" -> {false, errors}
      _ -> {default, add_error(errors, field, "must be a boolean")}
    end
  end

  defp parse_int(value) when is_integer(value), do: {:ok, value}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error

  defp add_error(errors, field, message) do
    Map.update(errors, field, [message], fn existing -> [message | existing] end)
  end

  defp build_result(errors, attrs) when map_size(errors) == 0, do: {:ok, attrs}

  defp build_result(errors, _attrs) do
    normalized =
      Enum.into(errors, %{}, fn {field, messages} ->
        {field, messages |> Enum.reverse() |> Enum.uniq()}
      end)

    {:error, {:validation, normalized}}
  end

  defp safe_existing_atom(nil), do: nil

  # Safe to use String.to_atom/1 here because values were already validated
  # against strict allow-lists in this module.
  defp safe_existing_atom(value) when is_binary(value), do: String.to_atom(value)

  defp completed_at_for("done"), do: DateTime.utc_now(:second)
  defp completed_at_for(_), do: nil
end
