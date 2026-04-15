defmodule Organizer.Planning.AttributeValidation do
  @moduledoc """
  Validation and normalization rules for planning attributes.
  """

  @task_statuses ~w(todo in_progress done)
  @task_priorities ~w(low medium high)
  @finance_kinds ~w(income expense)
  @goal_horizons ~w(short medium long)
  @goal_statuses ~w(active paused done)

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
    {amount_cents, errors} = validate_positive_int(attrs, :amount_cents, errors)
    {category, errors} = validate_required_string(attrs, :category, 2, 80, errors)
    {description, errors} = validate_optional_string(attrs, :description, 300, errors)

    {occurred_on, errors} =
      validate_date_with_default(attrs, :occurred_on, Date.utc_today(), errors)

    build_result(errors, %{
      kind: safe_existing_atom(kind),
      amount_cents: amount_cents,
      category: category,
      description: description,
      occurred_on: occurred_on
    })
  end

  def validate_goal_attrs(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    {title, errors} = validate_required_string(attrs, :title, 3, 140, %{})
    {horizon, errors} = validate_enum(attrs, :horizon, @goal_horizons, nil, errors)
    {status, errors} = validate_enum(attrs, :status, @goal_statuses, "active", errors)
    {target_value, errors} = validate_optional_positive_int(attrs, :target_value, errors)
    {current_value, errors} = validate_non_negative_int(attrs, :current_value, 0, errors)
    {due_on, errors} = validate_optional_date(attrs, :due_on, errors)
    {notes, errors} = validate_optional_string(attrs, :notes, 500, errors)

    build_result(errors, %{
      title: title,
      horizon: safe_existing_atom(horizon),
      status: safe_existing_atom(status),
      target_value: target_value,
      current_value: current_value,
      due_on: due_on,
      notes: notes
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

  defp parse_date(value, field, errors) do
    value
    |> String.trim()
    |> Date.from_iso8601()
    |> case do
      {:ok, parsed} -> {parsed, errors}
      _ -> {nil, add_error(errors, field, "must be in YYYY-MM-DD format")}
    end
  end

  defp validate_positive_int(attrs, field, errors) do
    case parse_int(Map.get(attrs, field)) do
      {:ok, number} when number > 0 -> {number, errors}
      {:ok, _number} -> {nil, add_error(errors, field, "must be greater than zero")}
      :error -> {nil, add_error(errors, field, "must be an integer")}
    end
  end

  defp validate_optional_positive_int(attrs, field, errors) do
    case Map.get(attrs, field) do
      nil ->
        {nil, errors}

      "" ->
        {nil, errors}

      value ->
        case parse_int(value) do
          {:ok, number} when number > 0 -> {number, errors}
          {:ok, _number} -> {nil, add_error(errors, field, "must be greater than zero")}
          :error -> {nil, add_error(errors, field, "must be an integer")}
        end
    end
  end

  defp validate_non_negative_int(attrs, field, default, errors) do
    case Map.get(attrs, field, default) do
      nil ->
        {default, errors}

      "" ->
        {default, errors}

      value ->
        case parse_int(value) do
          {:ok, number} when number >= 0 -> {number, errors}
          {:ok, _number} -> {default, add_error(errors, field, "must be zero or positive")}
          :error -> {default, add_error(errors, field, "must be an integer")}
        end
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
  defp safe_existing_atom(value), do: String.to_existing_atom(value)

  defp completed_at_for("done"), do: DateTime.utc_now(:second)
  defp completed_at_for(_), do: nil
end
