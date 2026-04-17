defmodule Organizer.Planning.BulkParser do
  @moduledoc """
  Parses lines from the bulk capture textarea into structured entry maps.

  Integrates `DateParser`, `AmountParser`, and `ContextInferrer` for
  enhanced natural-language format support on top of the explicit `campo=valor`
  syntax already supported.
  """

  alias Organizer.Planning.AmountParser
  alias Organizer.Planning.ContextInferrer
  alias Organizer.Planning.DateParser

  @doc """
  Parses a single line from the bulk textarea.

  Returns a map with keys:
    :type    - :task | :finance | :goal
    :status  - :valid | :invalid | :ignored
    :raw     - original line string
    :attrs   - map of string-keyed attributes
    :inferred_fields - list of field names that were inferred (vs explicit)
    :error   - error message string (only when status: :invalid)

  opts can include:
    :reference_date - Date.t() for relative date resolution (default: Date.utc_today())
  """
  @spec parse_line(String.t(), map()) :: map()
  def parse_line(line, opts \\ %{}) do
    reference_date = Map.get(opts, :reference_date, Date.utc_today())
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        %{raw: line, status: :ignored, attrs: %{}, inferred_fields: []}

      String.starts_with?(trimmed, "#") ->
        %{raw: line, status: :ignored, attrs: %{}, inferred_fields: []}

      String.contains?(trimmed, ":") ->
        [raw_type, raw_body] = String.split(trimmed, ":", parts: 2)
        type = normalize_token(raw_type)
        body = String.trim(raw_body)

        cond do
          type in ["tarefa", "task", "t"] ->
            parse_task_line(body, line, reference_date)

          type in ["financeiro", "finance", "lancamento", "lanc", "fin", "f"] ->
            parse_finance_line(body, nil, line, reference_date)

          type in ["meta", "goal", "g"] ->
            parse_goal_line(body, line, reference_date)

          type in ["receita", "despesa", "income", "expense"] ->
            parse_finance_line(body, type, line, reference_date)

          true ->
            %{
              raw: line,
              status: :invalid,
              error: "tipo não reconhecido. Use: tarefa, financeiro ou meta",
              attrs: %{},
              inferred_fields: []
            }
        end

      true ->
        %{
          raw: line,
          status: :invalid,
          error: "formato inválido. Use o padrão tipo: conteúdo",
          attrs: %{},
          inferred_fields: []
        }
    end
  end

  @doc """
  Parses multiple lines. Empty lines and lines starting with # are :ignored.
  """
  @spec parse_lines([String.t()], map()) :: [map()]
  def parse_lines(lines, opts \\ %{}) do
    Enum.map(lines, &parse_line(&1, opts))
  end

  # ---------------------------------------------------------------------------
  # Task parsing
  # ---------------------------------------------------------------------------

  defp parse_task_line(body, raw, reference_date) do
    if String.trim(body) == "" do
      %{
        raw: raw,
        status: :invalid,
        error: "título obrigatório para tarefa",
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
            error: "título obrigatório para tarefa",
            attrs: %{},
            inferred_fields: []
          }

        [title_raw | rest] ->
          kv = parse_kv_segments(rest)
          inferred = []

          # Extract explicit fields
          explicit_priority = map_priority(map_get_any(kv, ["prioridade", "priority", "prio"]))

          explicit_due_on =
            normalize_date_token(map_get_any(kv, ["data", "date", "due", "vencimento"]))

          explicit_status = map_task_status(map_get_any(kv, ["status"]))

          # Working title — may shrink as we extract inline hints
          working_title = title_raw

          # Enhancement 2: Extract priority from free text if not explicit
          {working_priority, working_title, inferred} =
            if is_nil(explicit_priority) do
              {extracted_priority, remaining_title} = extract_priority_from_text(working_title)

              if extracted_priority do
                {extracted_priority, remaining_title, [:priority | inferred]}
              else
                {nil, working_title, inferred}
              end
            else
              {explicit_priority, working_title, inferred}
            end

          priority = fallback(explicit_priority, working_priority)

          # Enhancement 1: Extract date from free text if not explicit
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

          # Apply defaults (Req 8)
          attrs =
            %{"title" => title}
            |> maybe_put("due_on", due_on)
            |> maybe_put("priority", priority)
            |> maybe_put("status", explicit_status)
            |> maybe_put("notes", map_get_any(kv, ["nota", "notas", "notes"]))
            |> Map.put_new("status", "todo")
            |> Map.put_new("priority", "medium")

          %{
            raw: raw,
            status: :valid,
            type: :task,
            attrs: attrs,
            inferred_fields: inferred
          }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Goal parsing
  # ---------------------------------------------------------------------------

  defp parse_goal_line(body, raw, reference_date) do
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

          # Enhancement 1: Extract date from free text if not explicit (for goals too)
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

          # Apply defaults (Req 8)
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
  # Finance parsing
  # ---------------------------------------------------------------------------

  defp parse_finance_line(body, declared_kind, raw, reference_date) do
    segments = split_pipe_segments(body)
    kv = parse_kv_segments(segments)

    free_segments =
      segments
      |> Enum.reject(&String.contains?(&1, "="))

    {kind, expense_profile, payment_method, amount_cents, category, occurred_on, description,
     inferred} =
      parse_finance_fields(kv, free_segments, declared_kind, reference_date)

    # Apply default occurred_on to today if nil (Req 8)
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

    # Enhancement 4: Use AmountParser for valor= and positional detection
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

    # Enhancement 3: ContextInferrer for kind if still nil
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
  # Detection helpers
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
          # First check if it's a plain ISO date token
          case Date.from_iso8601(normalized) do
            {:ok, _date} ->
              normalized

            _ ->
              # Try DateParser for relative expressions
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
      tokens
      |> Enum.reject(fn token ->
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
  # Priority extraction from free text (Enhancement 2)
  # ---------------------------------------------------------------------------

  # Ordered by specificity (multi-word patterns first)
  @priority_patterns [
    {"alta prioridade", "high"},
    {"prioridade alta", "high"},
    {"prioridade=alta", "high"},
    {"alta", "high"},
    {"urgente", "high"},
    {"prioridade media", "medium"},
    {"media", "medium"},
    {"baixa prioridade", "low"},
    {"prioridade baixa", "low"},
    {"baixa", "low"}
  ]

  defp extract_priority_from_text(text) do
    lowered = String.downcase(text)

    result =
      Enum.find_value(@priority_patterns, fn {pattern, priority} ->
        if String.contains?(lowered, pattern) do
          {priority, pattern}
        else
          nil
        end
      end)

    case result do
      {priority, matched_pattern} ->
        # Remove the matched pattern from title (case-insensitive)
        remaining =
          Regex.replace(
            ~r/\b#{Regex.escape(matched_pattern)}\b/ui,
            text,
            ""
          )
          |> String.trim()
          |> String.replace(~r/\s{2,}/, " ")

        {priority, remaining}

      nil ->
        {nil, text}
    end
  end

  # ---------------------------------------------------------------------------
  # Amount parsing via AmountParser (Enhancement 4)
  # ---------------------------------------------------------------------------

  defp parse_amount_via_parser(nil), do: nil

  defp parse_amount_via_parser(value) do
    case AmountParser.parse(value) do
      {:ok, cents} -> cents
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Segment splitting and kv parsing
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

  # ---------------------------------------------------------------------------
  # Mapping helpers
  # ---------------------------------------------------------------------------

  defp map_get_any(map, keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp map_priority(nil), do: nil

  defp map_priority(value) do
    case normalize_token(value) do
      "baixa" -> "low"
      "low" -> "low"
      "b" -> "low"
      "media" -> "medium"
      "média" -> "medium"
      "medium" -> "medium"
      "normal" -> "medium"
      "m" -> "medium"
      "alta" -> "high"
      "high" -> "high"
      "urgente" -> "high"
      "h" -> "high"
      _ -> nil
    end
  end

  defp map_task_status(nil), do: nil

  defp map_task_status(value) do
    case normalize_token(value) do
      "todo" -> "todo"
      "pendente" -> "todo"
      "in_progress" -> "in_progress"
      "andamento" -> "in_progress"
      "em_andamento" -> "in_progress"
      "done" -> "done"
      "concluida" -> "done"
      "concluída" -> "done"
      _ -> nil
    end
  end

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
  # Date helpers
  # ---------------------------------------------------------------------------

  defp normalize_date_token(nil), do: nil
  defp normalize_date_token(%Date{} = date), do: Date.to_iso8601(date)

  defp normalize_date_token(value) when is_binary(value) do
    cleaned = String.trim(value)

    case normalize_token(cleaned) do
      "hoje" ->
        Date.to_iso8601(Date.utc_today())

      "amanha" ->
        Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      "amanhã" ->
        Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      "ontem" ->
        Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

      _ ->
        normalize_explicit_date(cleaned)
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
  # General helpers
  # ---------------------------------------------------------------------------

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_token(value), do: value |> to_string() |> normalize_token()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fallback(nil, value), do: value
  defp fallback(value, _other), do: value
end
