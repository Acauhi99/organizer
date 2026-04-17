defmodule Organizer.Planning.DateParser do
  @moduledoc """
  Parses Portuguese date expressions into `%Date{}` values.

  Supports relative expressions like "hoje", "amanhã", weekdays, etc.
  All comparisons are done after Unicode normalization (NFD + strip combining chars).
  """

  @combining_char_range 0x0300..0x036F

  @doc """
  Resolves a date expression (relative or ISO 8601) to a `%Date{}`.

  Accepts Portuguese expressions: "amanhã", "próxima segunda", etc.
  The `reference_date` parameter is the base date (default: `Date.utc_today()`).

  Returns `{:ok, %Date{}}` or `{:error, :unrecognized_expression}`. Never raises.
  """
  @spec resolve(String.t(), Date.t()) :: {:ok, Date.t()} | {:error, :unrecognized_expression}
  def resolve(expression, reference_date \\ Date.utc_today())

  def resolve(expression, reference_date) when is_binary(expression) do
    # ISO 8601 idempotency: valid ISO date strings are returned unchanged
    case Date.from_iso8601(String.trim(expression)) do
      {:ok, date} ->
        {:ok, date}

      _ ->
        expression
        |> normalize()
        |> resolve_expression(reference_date)
    end
  end

  def resolve(_expression, _reference_date), do: {:error, :unrecognized_expression}

  @doc """
  Extracts the first date expression found in free text.

  Returns `{resolved_date_or_nil, remaining_text}` with the matched expression
  removed from the text. If no expression is found, returns `{nil, original_text}`.
  """
  @spec extract_from_text(String.t(), Date.t()) :: {Date.t() | nil, String.t()}
  def extract_from_text(text, reference_date \\ Date.utc_today())

  def extract_from_text(text, reference_date) when is_binary(text) do
    case find_and_extract(text, reference_date) do
      {date, remaining} -> {date, String.trim(remaining)}
      nil -> {nil, text}
    end
  end

  def extract_from_text(text, _reference_date), do: {nil, text}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp normalize(str) do
    str
    |> String.downcase()
    |> then(fn s ->
      case :unicode.characters_to_nfd_binary(s) do
        nfd when is_binary(nfd) ->
          nfd
          |> String.codepoints()
          |> Enum.reject(fn cp ->
            <<code::utf8>> = cp
            code in @combining_char_range
          end)
          |> IO.iodata_to_binary()

        _ ->
          s
      end
    end)
  end

  defp resolve_expression("hoje", ref), do: {:ok, ref}
  defp resolve_expression("amanha", ref), do: {:ok, Date.add(ref, 1)}
  defp resolve_expression("depois de amanha", ref), do: {:ok, Date.add(ref, 2)}
  defp resolve_expression("semana que vem", ref), do: {:ok, next_monday(ref)}
  defp resolve_expression("proxima semana", ref), do: {:ok, next_monday(ref)}
  defp resolve_expression("proximo mes", ref), do: {:ok, first_day_of_next_month(ref)}

  defp resolve_expression("proxima " <> weekday_str, ref) do
    case weekday_number(weekday_str) do
      {:ok, dow} -> {:ok, next_weekday(ref, dow)}
      :error -> {:error, :unrecognized_expression}
    end
  end

  defp resolve_expression(expr, ref) do
    case weekday_number(expr) do
      {:ok, dow} -> {:ok, next_weekday(ref, dow)}
      :error -> {:error, :unrecognized_expression}
    end
  end

  defp weekday_number("segunda"), do: {:ok, 1}
  defp weekday_number("terca"), do: {:ok, 2}
  defp weekday_number("quarta"), do: {:ok, 3}
  defp weekday_number("quinta"), do: {:ok, 4}
  defp weekday_number("sexta"), do: {:ok, 5}
  defp weekday_number("sabado"), do: {:ok, 6}
  defp weekday_number("domingo"), do: {:ok, 7}
  defp weekday_number(_), do: :error

  # Returns the next Monday strictly after `ref`
  defp next_monday(ref) do
    days = Integer.mod(8 - Date.day_of_week(ref), 7)
    days = if days == 0, do: 7, else: days
    Date.add(ref, days)
  end

  # Returns the next occurrence of `dow` strictly after `ref` (never same day)
  defp next_weekday(ref, dow) do
    ref_dow = Date.day_of_week(ref)
    days = Integer.mod(dow - ref_dow, 7)
    days = if days == 0, do: 7, else: days
    Date.add(ref, days)
  end

  defp first_day_of_next_month(%Date{year: year, month: 12}) do
    Date.new!(year + 1, 1, 1)
  end

  defp first_day_of_next_month(%Date{year: year, month: month}) do
    Date.new!(year, month + 1, 1)
  end

  # Ordered list of normalized patterns (longest first to avoid partial matches)
  @patterns [
    "depois de amanha",
    "semana que vem",
    "proxima semana",
    "proximo mes",
    "proxima segunda",
    "proxima terca",
    "proxima quarta",
    "proxima quinta",
    "proxima sexta",
    "proxima sabado",
    "proxima domingo",
    "amanha",
    "hoje",
    "segunda",
    "terca",
    "quarta",
    "quinta",
    "sexta",
    "sabado",
    "domingo"
  ]

  defp find_and_extract(text, reference_date) do
    normalized_text = normalize(text)

    Enum.find_value(@patterns, fn pattern ->
      case find_pattern_position(normalized_text, pattern) do
        nil ->
          nil

        {norm_start, norm_len} ->
          # Map norm byte offsets back to original text offsets
          case map_norm_to_orig(text, norm_start, norm_len) do
            {orig_start, orig_len} ->
              original_fragment = binary_part(text, orig_start, orig_len)

              case resolve(original_fragment, reference_date) do
                {:ok, date} ->
                  remaining = remove_at(text, orig_start, orig_len)
                  {date, remaining}

                _ ->
                  nil
              end

            nil ->
              nil
          end
      end
    end)
  end

  defp find_pattern_position(normalized_text, pattern) do
    case :binary.match(normalized_text, pattern) do
      :nomatch -> nil
      {start, len} -> {start, len}
    end
  end

  # Walk the original text codepoint-by-codepoint, tracking both the original
  # byte position and the corresponding position in the normalized string.
  # Since @patterns contain only ASCII (already normalized), combining characters
  # in the original text simply advance the orig pointer without advancing the
  # norm pointer.
  defp map_norm_to_orig(original_text, norm_start, norm_len) do
    codepoints = String.codepoints(original_text)

    {orig_start, orig_end, _, _, _} =
      Enum.reduce(codepoints, {nil, nil, 0, 0, false}, fn cp, {s, e, np, op, done} ->
        if done do
          {s, e, np, op, done}
        else
          <<codepoint::utf8>> = cp
          cp_bytes = byte_size(cp)
          is_combining = codepoint in @combining_char_range

          # Combining chars don't appear in normalized string
          norm_cp_bytes = if is_combining, do: 0, else: byte_size(normalize(cp))

          # Mark start when norm position reaches norm_start
          s2 =
            if s == nil and np == norm_start do
              op
            else
              s
            end

          new_np = np + norm_cp_bytes
          new_op = op + cp_bytes

          # Mark end when we've consumed norm_len bytes in normalized string
          {e2, done2} =
            if s2 != nil and e == nil and new_np >= norm_start + norm_len do
              {new_op, true}
            else
              {e, false}
            end

          {s2, e2, new_np, new_op, done2}
        end
      end)

    if orig_start != nil and orig_end != nil do
      {orig_start, orig_end - orig_start}
    else
      nil
    end
  end

  defp remove_at(text, start_byte, byte_len) do
    before = binary_part(text, 0, start_byte)
    rest_start = start_byte + byte_len
    rest_len = byte_size(text) - rest_start
    after_part = binary_part(text, rest_start, rest_len)

    (before <> " " <> after_part)
    |> String.trim()
    |> String.replace(~r/\s{2,}/, " ")
  end
end
