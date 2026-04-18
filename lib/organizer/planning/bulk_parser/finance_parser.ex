defmodule Organizer.Planning.BulkParser.FinanceParser do
  @moduledoc """
  Parses finance lines from the bulk capture textarea.

  Handles the `financeiro:` / `finance:` / `f:` / `receita:` / `despesa:`
  prefix formats, extracting kind, expense_profile, payment_method,
  amount_cents, category, occurred_on and description.
  """

  alias Organizer.Planning.AmountParser
  alias Organizer.Planning.ContextInferrer
  alias Organizer.Planning.DateParser

  @doc """
  Parses a finance body (everything after the type prefix) into a result map.

  `declared_kind` is non-nil when the prefix itself encodes the kind
  (e.g. `receita:` → `"receita"`, `despesa:` → `"despesa"`).
  """
  @spec parse(String.t(), String.t() | nil, String.t(), Date.t()) :: map()
  def parse(body, declared_kind, raw, reference_date) do
    segments = split_pipe_segments(body)
    kv = parse_kv_segments(segments)

    free_segments = Enum.reject(segments, &String.contains?(&1, "="))

    {kind, expense_profile, payment_method, amount_cents, category, occurred_on, description,
     inferred} =
      parse_finance_fields(kv, free_segments, declared_kind, reference_date)

    {occurred_on, inferred} =
      if is_nil(occurred_on) do
        {Date.to_iso8601(Date.utc_today()), [:occurred_on | inferred]}
      else
        {occurred_on, inferred}
      end

    attrs =
      %{}
      |> maybe_put("kind", kind)
      |> maybe_put("expense_profile", expense_profile)
      |> maybe_put("payment_method", payment_method)
      |> maybe_put("amount_cents", amount_cents)
      |> maybe_put("category", category)
      |> maybe_put("occurred_on", occurred_on)
      |> maybe_put("description", description)

    %{
      raw: raw,
      status: :valid,
      type: :finance,
      attrs: attrs,
      inferred_fields: inferred
    }
  end

  # ---------------------------------------------------------------------------
  # Field extraction
  # ---------------------------------------------------------------------------

  defp parse_finance_fields(kv, free_segments, declared_kind, reference_date) do
    free_tokens =
      free_segments
      |> Enum.join(" ")
      |> String.split(~r/\s+/, trim: true)

    inferred = []

    kind =
      declared_kind
      |> map_finance_kind()
      |> fallback(map_finance_kind(map_get_any(kv, ["tipo", "kind"])))
      |> fallback(detect_kind_in_tokens(free_tokens))

    expense_profile =
      map_get_any(kv, [
        "natureza",
        "perfil",
        "recorrencia",
        "recorrência",
        "expense_profile",
        "tipo_despesa"
      ])
      |> map_expense_profile()
      |> fallback(detect_expense_profile_in_tokens(free_tokens))

    payment_method =
      map_get_any(kv, ["pagamento", "meio", "metodo", "método", "payment_method", "forma"])
      |> map_payment_method()
      |> fallback(detect_payment_method_in_tokens(free_tokens))

    amount_cents =
      parse_amount_via_parser(map_get_any(kv, ["valor", "amount", "centavos", "amount_cents"])) ||
        detect_amount_in_tokens(free_tokens)

    occurred_on =
      normalize_date_token(map_get_any(kv, ["data", "date", "quando", "occurred_on"]))
      |> then(fn date ->
        if is_nil(date) do
          detect_date_in_tokens(free_tokens, reference_date)
        else
          date
        end
      end)

    category =
      map_get_any(kv, ["categoria", "category"]) ||
        detect_category_in_tokens(
          free_tokens,
          kind,
          expense_profile,
          payment_method,
          amount_cents,
          occurred_on
        )

    description = map_get_any(kv, ["descricao", "description", "desc"])

    {kind, inferred} =
      if is_nil(kind) do
        context_text = Enum.join([category, description] |> Enum.reject(&is_nil/1), " ")

        if context_text != "" do
          case ContextInferrer.infer_kind(context_text) do
            {:ok, inferred_kind} when not is_nil(inferred_kind) ->
              {Atom.to_string(inferred_kind), [:kind | inferred]}

            _ ->
              {nil, inferred}
          end
        else
          {nil, inferred}
        end
      else
        {kind, inferred}
      end

    {kind, expense_profile, payment_method, amount_cents, category, occurred_on, description,
     inferred}
  end

  # ---------------------------------------------------------------------------
  # Token detection helpers
  # ---------------------------------------------------------------------------

  defp detect_kind_in_tokens(tokens) do
    Enum.find_value(tokens, &map_finance_kind/1)
  end

  defp detect_amount_in_tokens(tokens) do
    Enum.find_value(tokens, &parse_amount_via_parser/1)
  end

  defp detect_expense_profile_in_tokens(tokens) do
    Enum.find_value(tokens, &map_expense_profile/1)
  end

  defp detect_payment_method_in_tokens(tokens) do
    Enum.find_value(tokens, &map_payment_method/1)
  end

  defp detect_date_in_tokens(tokens, reference_date) do
    Enum.find_value(tokens, fn token ->
      case normalize_date_token(token) do
        nil ->
          nil

        normalized when is_binary(normalized) ->
          case Date.from_iso8601(normalized) do
            {:ok, _date} ->
              normalized

            _ ->
              case DateParser.resolve(token, reference_date) do
                {:ok, date} -> Date.to_iso8601(date)
                _ -> nil
              end
          end
      end
    end)
  end

  defp detect_category_in_tokens(
         tokens,
         kind,
         expense_profile,
         payment_method,
         amount_cents,
         occurred_on
       ) do
    cleaned =
      Enum.reject(tokens, fn token ->
        (not is_nil(kind) and map_finance_kind(token) == kind) or
          (not is_nil(expense_profile) and map_expense_profile(token) == expense_profile) or
          (not is_nil(payment_method) and map_payment_method(token) == payment_method) or
          (not is_nil(amount_cents) and parse_amount_via_parser(token) == amount_cents) or
          (not is_nil(occurred_on) and normalize_date_token(token) == occurred_on)
      end)

    case cleaned do
      [] -> nil
      [first | _] -> first
    end
  end

  # ---------------------------------------------------------------------------
  # Amount parsing
  # ---------------------------------------------------------------------------

  defp parse_amount_via_parser(nil), do: nil

  defp parse_amount_via_parser(value) do
    case AmountParser.parse(value) do
      {:ok, cents} -> cents
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Mapping helpers
  # ---------------------------------------------------------------------------

  defp map_finance_kind(nil), do: nil

  defp map_finance_kind(value) do
    case normalize_token(value) do
      "receita" -> "income"
      "income" -> "income"
      "despesa" -> "expense"
      "expense" -> "expense"
      _ -> nil
    end
  end

  defp map_expense_profile(nil), do: nil

  defp map_expense_profile(value) do
    case normalize_token(value) do
      "fixed" -> "fixed"
      "fixa" -> "fixed"
      "fixo" -> "fixed"
      "recorrente" -> "fixed"
      "mensal" -> "fixed"
      "variable" -> "variable"
      "variavel" -> "variable"
      "variável" -> "variable"
      "avulsa" -> "variable"
      "pontual" -> "variable"
      _ -> nil
    end
  end

  defp map_payment_method(nil), do: nil

  defp map_payment_method(value) do
    case normalize_token(value) do
      "credit" -> "credit"
      "credito" -> "credit"
      "crédito" -> "credit"
      "cartao" -> "credit"
      "cartão" -> "credit"
      "cartao_credito" -> "credit"
      "cartão_crédito" -> "credit"
      "debit" -> "debit"
      "debito" -> "debit"
      "débito" -> "debit"
      "cartao_debito" -> "debit"
      "cartão_débito" -> "debit"
      "pix" -> "debit"
      "dinheiro" -> "debit"
      _ -> nil
    end
  end

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
