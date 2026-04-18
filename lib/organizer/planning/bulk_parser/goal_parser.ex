defmodule Organizer.Planning.BulkParser.GoalParser do
  @moduledoc """
  Parses goal lines from the bulk capture textarea.

  Handles the `meta:` / `goal:` / `g:` prefix format, extracting title,
  horizon, status, target_value, current_value, due_on and notes.
  Supports natural-language date hints embedded in the free-text title.
  """

  alias Organizer.Planning.DateParser

  @doc """
  Parses a goal body (everything after the `meta:` prefix) into a result map.
  """
  @spec parse(String.t(), String.t(), Date.t()) :: map()
  def parse(body, raw, reference_date) do
    if String.trim(body) == "" do
      %{
        raw: raw,
        status: :invalid,
        error: "título obrigatório para meta",
        attrs: %{},
        inferred_fields: []
      }
    else
      segments = split_pipe_segments(body)

      case segments do
        [] ->
          %{
            raw: raw,
            status: :invalid,
            error: "título obrigatório para meta",
            attrs: %{},
            inferred_fields: []
          }

        [title_raw | rest] ->
          kv = parse_kv_segments(rest)
          inferred = []

          explicit_due_on =
            normalize_date_token(map_get_any(kv, ["data", "date", "due", "prazo"]))

          working_title = title_raw

          {working_due_on, working_title, inferred} =
            if is_nil(explicit_due_on) do
              {extracted_date, remaining_title} =
                DateParser.extract_from_text(working_title, reference_date)

              if extracted_date do
                {Date.to_iso8601(extracted_date), remaining_title, [:due_on | inferred]}
              else
                {nil, working_title, inferred}
              end
            else
              {explicit_due_on, working_title, inferred}
            end

          due_on = fallback(explicit_due_on, working_due_on)
          title = String.trim(working_title)

          attrs =
            %{"title" => title}
            |> maybe_put("horizon", map_goal_horizon(map_get_any(kv, ["horizonte", "horizon"])))
            |> maybe_put("status", map_goal_status(map_get_any(kv, ["status"])))
            |> maybe_put(
              "target_value",
              parse_int_token(map_get_any(kv, ["alvo", "target", "target_value"]))
            )
            |> maybe_put(
              "current_value",
              parse_int_token(map_get_any(kv, ["atual", "current", "current_value"]))
            )
            |> maybe_put("due_on", due_on)
            |> maybe_put("notes", map_get_any(kv, ["nota", "notas", "notes"]))
            |> Map.put_new("horizon", "medium")
            |> Map.put_new("status", "active")

          %{
            raw: raw,
            status: :valid,
            type: :goal,
            attrs: attrs,
            inferred_fields: inferred
          }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Mapping helpers
  # ---------------------------------------------------------------------------

  defp map_goal_horizon(nil), do: nil

  defp map_goal_horizon(value) do
    case normalize_token(value) do
      "curto" -> "short"
      "short" -> "short"
      "medio" -> "medium"
      "médio" -> "medium"
      "medium" -> "medium"
      "longo" -> "long"
      "long" -> "long"
      _ -> nil
    end
  end

  defp map_goal_status(nil), do: nil

  defp map_goal_status(value) do
    case normalize_token(value) do
      "active" -> "active"
      "ativa" -> "active"
      "paused" -> "paused"
      "pausada" -> "paused"
      "done" -> "done"
      "concluida" -> "done"
      "concluída" -> "done"
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Integer parsing helper
  # ---------------------------------------------------------------------------

  defp parse_int_token(nil), do: nil
  defp parse_int_token(value) when is_integer(value), do: value

  defp parse_int_token(value) when is_binary(value) do
    cleaned =
      value
      |> String.trim()
      |> String.replace(~r/[^0-9-]/u, "")

    case Integer.parse(cleaned) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int_token(_), do: nil

  # ---------------------------------------------------------------------------
  # Shared segment / kv / date / general helpers
  # ---------------------------------------------------------------------------

  defp split_pipe_segments(body) do
    body
    |> String.split("|", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_kv_segments(segments) do
    Enum.reduce(segments, %{}, fn segment, acc ->
      case String.split(segment, "=", parts: 2) do
        [key, value] -> Map.put(acc, normalize_token(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp map_get_any(map, keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp normalize_date_token(nil), do: nil
  defp normalize_date_token(%Date{} = date), do: Date.to_iso8601(date)

  defp normalize_date_token(value) when is_binary(value) do
    cleaned = String.trim(value)

    case normalize_token(cleaned) do
      "hoje" -> Date.to_iso8601(Date.utc_today())
      "amanha" -> Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      "amanhã" -> Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      "ontem" -> Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      _ -> normalize_explicit_date(cleaned)
    end
  end

  defp normalize_date_token(_), do: nil

  defp normalize_explicit_date(cleaned) do
    case Date.from_iso8601(cleaned) do
      {:ok, date} ->
        Date.to_iso8601(date)

      _ ->
        with [y, m, d] <-
               Regex.run(~r/^(\d{4})[\/\-\.](\d{1,2})[\/\-\.](\d{1,2})$/u, cleaned,
                 capture: :all_but_first
               ),
             {year, ""} <- Integer.parse(y),
             {month, ""} <- Integer.parse(m),
             {day, ""} <- Integer.parse(d),
             {:ok, date} <- Date.new(year, month, day) do
          Date.to_iso8601(date)
        else
          _ ->
            with [a, b, y] <-
                   Regex.run(~r/^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})$/u, cleaned,
                     capture: :all_but_first
                   ),
                 {da, ""} <- Integer.parse(a),
                 {db, ""} <- Integer.parse(b),
                 {dy, ""} <- Integer.parse(y),
                 {year, month, day} <- infer_date_parts(da, db, dy),
                 {:ok, date} <- Date.new(year, month, day) do
              Date.to_iso8601(date)
            else
              _ -> cleaned
            end
        end
    end
  end

  defp infer_date_parts(a, b, y) when a > 12, do: {y, b, a}
  defp infer_date_parts(a, b, y) when b > 12, do: {y, a, b}
  defp infer_date_parts(a, b, y), do: {y, b, a}

  defp normalize_token(value) when is_binary(value) do
    value |> String.trim() |> String.downcase()
  end

  defp normalize_token(value), do: value |> to_string() |> normalize_token()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fallback(nil, value), do: value
  defp fallback(value, _other), do: value
end
