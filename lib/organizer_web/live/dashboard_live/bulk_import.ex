defmodule OrganizerWeb.DashboardLive.BulkImport do
  @moduledoc """
  Encapsula toda a lógica de bulk import: parsing, preview, importação,
  desfazer, correções e templates.
  """

  alias Organizer.Planning
  alias Organizer.Planning.{AttributeValidation, BulkParser, BulkScoring, FieldSuggester}
  import Phoenix.Component, only: [assign: 3]

  @spec preview_bulk_payload(String.t()) :: map()
  def preview_bulk_payload(payload) do
    entries =
      payload
      |> to_string()
      |> String.split(~r/\R/u, trim: false)
      |> Enum.with_index(1)
      |> Enum.map(fn {line, line_number} ->
        build_bulk_preview_entry(line, line_number)
      end)

    # Add scoring information for confidence-based feedback
    scoring = BulkScoring.score_entries(entries)

    %{
      entries: entries,
      lines_total: length(entries),
      valid_total: Enum.count(entries, &(&1.status == :valid)),
      invalid_total: Enum.count(entries, &(&1.status == :invalid)),
      ignored_total: Enum.count(entries, &(&1.status == :ignored)),
      scoring: scoring
    }
  end

  @spec import_bulk_payload(String.t(), scope :: term(), preview :: map()) :: map()
  def import_bulk_payload(_payload, scope, preview) do
    import_preview_entries(scope, preview.entries, preview)
  end

  @spec import_preview_entries(scope :: term(), entries :: list(), source_preview :: map()) ::
          map()
  def import_preview_entries(scope, entries, source_preview) do
    base = %{
      created: %{tasks: 0, finances: 0, goals: 0},
      errors:
        entries
        |> Enum.filter(&(&1.status == :invalid))
        |> Enum.map(fn entry -> "Linha #{entry.line_number}: #{entry.error}" end),
      preview: source_preview,
      last_bulk_import: nil
    }

    {result, imported_ids} =
      Enum.reduce(entries, {base, %{tasks: [], finances: [], goals: []}}, fn entry, {acc, ids} ->
        case entry do
          %{status: :valid, type: :task, attrs: attrs, line_number: line_number} ->
            case Planning.create_task(scope, attrs) do
              {:ok, task} ->
                {
                  increment_bulk_count(acc, :tasks),
                  Map.update!(ids, :tasks, fn values -> [task.id | values] end)
                }

              {:error, {:validation, details}} ->
                {add_bulk_error(acc, line_number, format_validation_errors(details)), ids}

              {:error, reason} ->
                {add_bulk_error(acc, line_number, inspect(reason)), ids}
            end

          %{status: :valid, type: :finance, attrs: attrs, line_number: line_number} ->
            case Planning.create_finance_entry(scope, attrs) do
              {:ok, finance} ->
                {
                  increment_bulk_count(acc, :finances),
                  Map.update!(ids, :finances, fn values -> [finance.id | values] end)
                }

              {:error, {:validation, details}} ->
                {add_bulk_error(acc, line_number, format_validation_errors(details)), ids}

              {:error, reason} ->
                {add_bulk_error(acc, line_number, inspect(reason)), ids}
            end

          %{status: :valid, type: :goal, attrs: attrs, line_number: line_number} ->
            case Planning.create_goal(scope, attrs) do
              {:ok, goal} ->
                {
                  increment_bulk_count(acc, :goals),
                  Map.update!(ids, :goals, fn values -> [goal.id | values] end)
                }

              {:error, {:validation, details}} ->
                {add_bulk_error(acc, line_number, format_validation_errors(details)), ids}

              {:error, reason} ->
                {add_bulk_error(acc, line_number, inspect(reason)), ids}
            end

          _ ->
            {acc, ids}
        end
      end)

    last_bulk_import =
      if total_bulk_created(result.created) > 0 do
        %{
          tasks: Enum.reverse(imported_ids.tasks),
          finances: Enum.reverse(imported_ids.finances),
          goals: Enum.reverse(imported_ids.goals)
        }
      else
        nil
      end

    FieldSuggester.record_import(entries, scope)

    %{result | last_bulk_import: last_bulk_import}
  end

  @spec undo_bulk_import(last_bulk_import :: map(), scope :: term()) :: map()
  def undo_bulk_import(last_bulk_import, scope) do
    {task_removed, task_errors} =
      undo_bulk_items(last_bulk_import.tasks, fn id ->
        Planning.delete_task(scope, id)
      end)

    {finance_removed, finance_errors} =
      undo_bulk_items(last_bulk_import.finances, fn id ->
        Planning.delete_finance_entry(scope, id)
      end)

    {goal_removed, goal_errors} =
      undo_bulk_items(last_bulk_import.goals, fn id ->
        Planning.delete_goal(scope, id)
      end)

    %{
      removed: %{tasks: task_removed, finances: finance_removed, goals: goal_removed},
      errors: task_errors ++ finance_errors ++ goal_errors
    }
  end

  @spec apply_bulk_fix_for_line(String.t(), pos_integer()) ::
          {:ok, String.t()} | {:error, atom()}
  def apply_bulk_fix_for_line(payload, line_number)
      when is_binary(payload) and line_number > 0 do
    preview = preview_bulk_payload(payload)

    case Enum.find(preview.entries, &(&1.line_number == line_number)) do
      %{status: :invalid, suggested_line: suggested_line}
      when is_binary(suggested_line) and suggested_line != "" ->
        lines = String.split(payload, ~r/\R/u, trim: false)

        if line_number <= length(lines) do
          {:ok, List.replace_at(lines, line_number - 1, suggested_line) |> Enum.join("\n")}
        else
          {:error, :line_out_of_bounds}
        end

      _ ->
        {:error, :no_fix_available}
    end
  end

  def apply_bulk_fix_for_line(_payload, _line_number), do: {:error, :invalid_input}

  @spec apply_all_bulk_fixes(String.t()) ::
          {:ok, String.t(), non_neg_integer()} | {:error, atom()}
  def apply_all_bulk_fixes(payload) when is_binary(payload) do
    preview = preview_bulk_payload(payload)
    lines = String.split(payload, ~r/\R/u, trim: false)
    line_count = length(lines)

    {fixed_lines, fixed_count} =
      Enum.reduce(preview.entries, {lines, 0}, fn entry, {acc_lines, acc_count} ->
        suggested_line = Map.get(entry, :suggested_line)

        if entry.status == :invalid and is_binary(suggested_line) and suggested_line != "" and
             entry.line_number <= line_count do
          {List.replace_at(acc_lines, entry.line_number - 1, suggested_line), acc_count + 1}
        else
          {acc_lines, acc_count}
        end
      end)

    {:ok, Enum.join(fixed_lines, "\n"), fixed_count}
  end

  def apply_all_bulk_fixes(_payload), do: {:error, :invalid_input}

  @spec bulk_template_payload(String.t()) :: String.t()
  def bulk_template_payload("mixed") do
    amanha = Date.to_iso8601(Date.add(Date.utc_today(), 1))

    """
    tarefa: reunião com equipe #{amanha}
    financeiro: almoço 35
    meta: aprender Elixir
    """
    |> String.trim()
  end

  def bulk_template_payload("tasks") do
    amanha = Date.to_iso8601(Date.add(Date.utc_today(), 1))

    """
    tarefa: revisar metas da semana #{amanha} alta
    tarefa: organizar documentos
    tarefa: planejar descanso baixa
    """
    |> String.trim()
  end

  def bulk_template_payload("finance") do
    today = Date.to_iso8601(Date.utc_today())

    """
    financeiro: almoço 35
    financeiro: salário 5000
    financeiro: uber #{today} 18,50
    """
    |> String.trim()
  end

  def bulk_template_payload("goals") do
    """
    meta: reserva de emergência horizonte=longo alvo=300000
    meta: aprender Elixir
    meta: rotina de treino horizonte=curto
    """
    |> String.trim()
  end

  def bulk_template_payload(_), do: ""

  @spec bulk_reference_markdown_template() :: String.t()
  def bulk_reference_markdown_template do
    today = Date.to_iso8601(Date.utc_today())
    tomorrow = Date.to_iso8601(Date.add(Date.utc_today(), 1))

    """
    # Organizer - Guia de Importacao Copy/Paste (Markdown)

    Use este guia para montar linhas de importacao no formato:

    `tipo: conteudo`

    ## Regras gerais

    - Uma linha = um item.
    - Campos opcionais: `| campo=valor`.
    - Linhas vazias e linhas iniciadas com `#` sao ignoradas.
    - Datas aceitas: `YYYY-MM-DD`, `DD/MM/YYYY`, `hoje`, `amanha`, `ontem`.

    ## Prefixos aceitos

    - Tarefa: `tarefa`, `task`, `t`
    - Financeiro: `financeiro`, `finance`, `lancamento`, `lanc`, `fin`, `f`, `receita`, `despesa`
    - Meta: `meta`, `goal`, `g`

    ## Tarefa

    Campos:
    - `data`, `date`, `due`, `vencimento`
    - `prioridade`, `priority`, `prio`
    - `status`
    - `nota`, `notas`, `notes`

    Prioridade:
    - baixa: `baixa`, `low`, `b`
    - media: `media`, `medio`, `medium`, `normal`, `m`
    - alta: `alta`, `high`, `urgente`, `h`

    Status:
    - `todo` (`pendente`)
    - `in_progress` (`andamento`, `em_andamento`)
    - `done` (`concluida`)

    Defaults:
    - `status=todo`
    - `prioridade=medium`

    Exemplos:
    - `tarefa: Revisar planejamento amanha alta`
    - `tarefa: Revisar planejamento | data=#{tomorrow} | prioridade=alta | status=todo`

    ## Financeiro

    Campos:
    - `tipo`, `kind` (income/expense)
    - `natureza`, `perfil`, `recorrencia`, `expense_profile`
    - `pagamento`, `meio`, `metodo`, `payment_method`
    - `valor`, `amount`, `centavos`, `amount_cents`
    - `categoria`, `category`
    - `data`, `date`, `quando`, `occurred_on`
    - `descricao`, `description`, `desc`

    Tipo:
    - receita: `receita`, `income`
    - despesa: `despesa`, `expense`

    Natureza (despesa):
    - fixa: `fixa`, `fixo`, `recorrente`, `mensal`
    - variavel: `variavel`, `avulsa`, `pontual`

    Pagamento (despesa):
    - credito: `credito`, `cartao`
    - debito: `debito`, `pix`, `dinheiro`

    Valor:
    - aceita `35`, `125,90`, `R$ 89,50`, `1k`

    Defaults:
    - sem data: usa `#{today}`
    - despesa sem natureza/pagamento: `natureza=variable`, `pagamento=debit`

    Exemplos:
    - `financeiro: almoco 35`
    - `financeiro: tipo=despesa | natureza=fixa | pagamento=credito | valor=125,90 | categoria=moradia | data=#{today}`

    ## Meta

    Campos:
    - `horizonte`, `horizon`
    - `status`
    - `alvo`, `target`, `target_value`
    - `atual`, `current`, `current_value`
    - `data`, `date`, `due`, `prazo`
    - `nota`, `notas`, `notes`

    Horizonte:
    - `short` (`curto`)
    - `medium` (`medio`)
    - `long` (`longo`)

    Status:
    - `active` (`ativa`)
    - `paused` (`pausada`)
    - `done` (`concluida`)

    Defaults:
    - `horizon=medium`
    - `status=active`
    - `current_value=0`

    Exemplos:
    - `meta: Reserva de emergencia`
    - `meta: Reserva de emergencia | horizonte=medio | alvo=300000 | atual=50000 | prazo=2026-12-31`
    """
    |> String.trim()
  end

  @spec remember_bulk_payload(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def remember_bulk_payload(socket, payload) when is_binary(payload) do
    trimmed = String.trim(payload)

    if trimmed == "" do
      socket
    else
      entry =
        case Enum.find(socket.assigns.bulk_recent_payloads, &(&1.payload == trimmed)) do
          nil ->
            %{
              id: System.unique_integer([:positive]),
              payload: trimmed,
              preview_line: preview_history_line(trimmed),
              favorite: false
            }

          existing ->
            %{
              existing
              | preview_line: preview_history_line(trimmed)
            }
        end

      history =
        [entry | Enum.reject(socket.assigns.bulk_recent_payloads, &(&1.payload == trimmed))]
        |> Enum.take(10)

      assign(socket, :bulk_recent_payloads, history)
    end
  end

  def remember_bulk_payload(socket, _payload), do: socket

  @spec current_bulk_import_block(map() | nil, pos_integer(), non_neg_integer()) :: map()
  def current_bulk_import_block(nil, _size, _index),
    do: %{entries: [], index: 0, total: 0}

  def current_bulk_import_block(preview, size, index) do
    safe_size = max(size, 1)

    blocks =
      preview.entries
      |> Enum.filter(&(&1.status == :valid))
      |> Enum.chunk_every(safe_size)

    total = length(blocks)
    safe_index = clamp_bulk_index(index, total)

    entries = if total > 0, do: Enum.at(blocks, safe_index, []), else: []

    %{entries: entries, index: safe_index, total: total}
  end

  @spec remove_bulk_payload_lines(String.t(), list(pos_integer())) :: String.t()
  def remove_bulk_payload_lines(payload, line_numbers) when is_binary(payload) do
    to_remove = MapSet.new(line_numbers)

    payload
    |> String.split(~r/\R/u, trim: false)
    |> Enum.with_index(1)
    |> Enum.reject(fn {_line, line_number} -> MapSet.member?(to_remove, line_number) end)
    |> Enum.map(fn {line, _line_number} -> line end)
    |> Enum.join("\n")
    |> String.trim()
  end

  def remove_bulk_payload_lines(payload, _line_numbers), do: payload

  @spec build_bulk_preview_entry(String.t(), pos_integer()) :: map()
  def build_bulk_preview_entry(raw_line, line_number) do
    line = String.trim(raw_line)
    entry = BulkParser.parse_line(raw_line)

    case entry.status do
      :ignored ->
        %{line_number: line_number, raw: line, status: :ignored}

      :invalid ->
        %{
          line_number: line_number,
          raw: line,
          status: :invalid,
          error: entry.error,
          suggested_line: suggest_bulk_fix(line, entry.error)
        }

      :valid ->
        case validate_preview_entry(entry.type, entry.attrs) do
          :ok ->
            %{
              line_number: line_number,
              raw: line,
              status: :valid,
              type: entry.type,
              attrs: entry.attrs,
              inferred_fields: entry.inferred_fields
            }

          {:error, reason, suggested_line} ->
            %{
              line_number: line_number,
              raw: line,
              status: :invalid,
              error: reason,
              suggested_line: suggested_line
            }
        end
    end
  end

  # Private helpers

  defp validate_preview_entry(:task, attrs) do
    case AttributeValidation.validate_task_attrs(attrs) do
      {:ok, _} ->
        :ok

      {:error, {:validation, details}} ->
        {:error, format_validation_errors(details), suggest_task_validation_fix(attrs, details)}
    end
  end

  defp validate_preview_entry(:finance, attrs) do
    case AttributeValidation.validate_finance_entry_attrs(attrs) do
      {:ok, _} ->
        :ok

      {:error, {:validation, details}} ->
        {:error, format_validation_errors(details),
         suggest_finance_validation_fix(attrs, details)}
    end
  end

  defp validate_preview_entry(:goal, attrs) do
    case AttributeValidation.validate_goal_attrs(attrs) do
      {:ok, _} ->
        :ok

      {:error, {:validation, details}} ->
        {:error, format_validation_errors(details), suggest_goal_validation_fix(attrs, details)}
    end
  end

  defp suggest_bulk_fix(line, reason) when is_binary(line) and is_binary(reason) do
    cond do
      String.contains?(reason, "formato inválido") -> suggest_missing_colon_fix(line)
      String.contains?(reason, "tipo não reconhecido") -> suggest_unknown_type_fix(line)
      true -> nil
    end
  end

  defp suggest_bulk_fix(_line, _reason), do: nil

  defp suggest_missing_colon_fix(line) do
    case String.split(line, ~r/\s+/, parts: 2, trim: true) do
      [raw_type, body] ->
        case canonical_bulk_type(raw_type) do
          {:task, _} -> "tarefa: " <> body
          {:goal, _} -> "meta: " <> body
          {:finance_kind, kind} -> "financeiro: " <> kind <> " " <> body
          {:finance, _} -> "financeiro: " <> body
          :unknown -> nil
        end

      _ ->
        nil
    end
  end

  defp suggest_unknown_type_fix(line) do
    case String.split(line, ":", parts: 2) do
      [raw_type, body] ->
        normalized_body = String.trim(body)

        case canonical_bulk_type(raw_type) do
          {:task, _} -> "tarefa: " <> normalized_body
          {:goal, _} -> "meta: " <> normalized_body
          {:finance_kind, kind} -> "financeiro: " <> kind <> " " <> normalized_body
          {:finance, _} -> "financeiro: " <> normalized_body
          :unknown -> nil
        end

      _ ->
        nil
    end
  end

  defp canonical_bulk_type(token) do
    case normalize_token(token) do
      value when value in ["tarefa", "task", "t"] ->
        {:task, "tarefa"}

      value when value in ["meta", "goal", "g", "objetivo"] ->
        {:goal, "meta"}

      value
      when value in ["financeiro", "finance", "lancamento", "lanc", "fin", "f"] ->
        {:finance, "financeiro"}

      value when value in ["receita", "despesa", "income", "expense"] ->
        {:finance_kind, value}

      _ ->
        :unknown
    end
  end

  defp suggest_task_validation_fix(attrs, details) do
    if Map.has_key?(details, :due_on) do
      title = Map.get(attrs, "title", "Nova tarefa")
      priority = Map.get(attrs, "priority", "medium")
      "tarefa: #{title} | prioridade=#{priority}"
    else
      nil
    end
  end

  defp suggest_finance_validation_fix(attrs, details) do
    if Enum.any?(
         [:kind, :amount_cents, :category, :occurred_on, :expense_profile, :payment_method],
         &Map.has_key?(details, &1)
       ) do
      attrs
      |> Map.put_new("kind", "expense")
      |> then(fn fixed ->
        if Map.get(fixed, "kind") == "expense" do
          fixed
          |> Map.put_new("expense_profile", "variable")
          |> Map.put_new("payment_method", "debit")
        else
          fixed
        end
      end)
      |> Map.put_new("amount_cents", 100)
      |> Map.put_new("category", "geral")
      |> Map.put_new("occurred_on", Date.to_iso8601(Date.utc_today()))
      |> then(fn fixed ->
        body =
          [
            "tipo=#{Map.get(fixed, "kind")}",
            Map.get(fixed, "kind") == "expense" &&
              "natureza=#{Map.get(fixed, "expense_profile")}",
            Map.get(fixed, "kind") == "expense" &&
              "pagamento=#{Map.get(fixed, "payment_method")}",
            "valor=#{Map.get(fixed, "amount_cents")}",
            "categoria=#{Map.get(fixed, "category")}",
            "data=#{Map.get(fixed, "occurred_on")}",
            Map.get(fixed, "description") && "descricao=#{Map.get(fixed, "description")}"
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" | ")

        "financeiro: " <> body
      end)
    else
      nil
    end
  end

  defp suggest_goal_validation_fix(attrs, details) do
    if Map.has_key?(details, :horizon) do
      title = Map.get(attrs, "title", "Nova meta")

      parts =
        [
          "horizonte=medium",
          Map.get(attrs, "target_value") && "alvo=#{Map.get(attrs, "target_value")}",
          Map.get(attrs, "status") && "status=#{Map.get(attrs, "status")}",
          Map.get(attrs, "due_on") && "data=#{Map.get(attrs, "due_on")}"
        ]
        |> Enum.reject(&is_nil/1)

      "meta: #{title} | " <> Enum.join(parts, " | ")
    else
      nil
    end
  end

  defp undo_bulk_items(ids, delete_fun) do
    Enum.reduce(ids, {0, []}, fn id, {removed, errors} ->
      case delete_fun.(id) do
        {:ok, _} ->
          {removed + 1, errors}

        {:error, :not_found} ->
          {removed, errors}

        {:error, reason} ->
          {removed, errors ++ ["item #{id}: #{inspect(reason)}"]}
      end
    end)
  end

  defp add_bulk_error(acc, line_number, message) do
    Map.update!(acc, :errors, fn errors ->
      errors ++ ["Linha #{line_number}: #{message}"]
    end)
  end

  defp increment_bulk_count(acc, key) do
    update_in(acc, [:created, key], &(&1 + 1))
  end

  defp format_validation_errors(details) when is_map(details) do
    details
    |> Enum.map(fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join(" | ")
  end

  defp format_validation_errors(details), do: inspect(details)

  defp preview_history_line(payload) do
    payload
    |> String.split(~r/\R/u, trim: true)
    |> List.first()
    |> case do
      nil -> "(vazio)"
      value -> value
    end
  end

  def toggle_string_flag(list, value) do
    if value in list do
      Enum.reject(list, &(&1 == value))
    else
      [value | list]
    end
  end

  def find_bulk_history_entry(history, id) do
    Enum.find(history, &(to_string(&1.id) == to_string(id)))
  end

  def bulk_block_total(nil, _size), do: 0

  def bulk_block_total(preview, size) do
    preview
    |> current_bulk_import_block(size, 0)
    |> Map.get(:total, 0)
  end

  def clamp_bulk_block_index(index, preview, size) do
    total = bulk_block_total(preview, size)
    clamp_bulk_index(index, total)
  end

  defp clamp_bulk_index(_index, total) when total <= 0, do: 0
  defp clamp_bulk_index(index, total), do: index |> max(0) |> min(total - 1)

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_token(value), do: value |> to_string() |> normalize_token()

  defp total_bulk_created(created) do
    created.tasks + created.finances + created.goals
  end

  def parse_index(value) when is_integer(value), do: value

  def parse_index(value) do
    case Integer.parse(to_string(value)) do
      {i, ""} -> i
      _ -> nil
    end
  end
end
