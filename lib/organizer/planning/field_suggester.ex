defmodule Organizer.Planning.FieldSuggester do
  @moduledoc """
  Frequency-based field value suggester using GenServer + ETS.

  Follows the AnalyticsCache pattern: named ETS table for concurrent reads,
  GenServer for lifecycle management. Provides graceful degradation to
  static canonical values when ETS is unavailable.

  ## ETS Table: :field_suggestions

  Two key formats:
  - Frequency: `{"freq", user_id, field_name, value}` → `{count, last_used_at}`
  - Correlation: `{"corr", user_id, field_a, val_a, field_b, val_b}` → count
  """

  use GenServer
  require Logger

  # Fields tracked per entry type for record_import/2
  @tracked_fields %{
    "task" => ["priority", "status"],
    "finance" => ["kind", "expense_profile", "payment_method", "category"],
    "goal" => ["horizon", "status"]
  }

  @canonical_values %{
    # Portuguese aliases
    "prioridade" => ["baixa", "media", "alta"],
    "priority" => ["baixa", "media", "alta"],
    "status" => ["fazer", "em_andamento", "concluido"],
    "horizonte" => ["curto", "medio", "longo"],
    "horizon" => ["curto", "medio", "longo"],
    "tipo" => ["despesa", "receita"],
    "kind" => ["despesa", "receita"],
    "natureza" => ["fixa", "variavel"],
    "expense_profile" => ["fixa", "variavel"],
    "pagamento" => ["debito", "credito"],
    "payment_method" => ["debito", "credito"]
  }

  # ===== Public API =====

  @doc """
  Start the FieldSuggester GenServer and ETS table.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Complete a partial field value prefix to the full canonical value.

  Returns:
  - `{:ok, value}` if exactly one canonical value matches
  - `{:ok, longest_common_prefix}` if multiple values match
  - `{:ok, nil}` if no match or unknown field
  """
  @spec complete(String.t(), map(), String.t()) :: {:ok, String.t() | nil}
  def complete(field_name, _scope, prefix) do
    case Map.get(@canonical_values, field_name) do
      nil ->
        {:ok, nil}

      canonical ->
        lower_prefix = String.downcase(prefix)

        matches =
          Enum.filter(canonical, fn value ->
            String.starts_with?(String.downcase(value), lower_prefix)
          end)

        case matches do
          [] -> {:ok, nil}
          [single] -> {:ok, single}
          multiple -> {:ok, longest_common_prefix(multiple)}
        end
    end
  rescue
    e ->
      Logger.error("FieldSuggester.complete error: #{inspect(e)}")
      {:ok, nil}
  end

  @doc """
  Return sorted list of suggested values for a field, ranked by user frequency DESC,
  recency DESC. Falls back to canonical list if no history.
  """
  @spec suggest_values(String.t(), map()) :: [String.t()]
  def suggest_values(field_name, scope) do
    user_id = scope.user.id

    case lookup_freq_entries(user_id, field_name) do
      [] ->
        Map.get(@canonical_values, field_name, [])

      entries ->
        entries
        |> Enum.sort_by(fn {count, last_used_at, _value} -> {-count, last_used_at} end)
        |> Enum.map(fn {_count, _last_used_at, value} -> value end)
    end
  rescue
    e ->
      Logger.error("FieldSuggester.suggest_values error: #{inspect(e)}")
      Map.get(@canonical_values, field_name, [])
  end

  @doc """
  Return [{field, value}] pairs with co-occurrence >= 3 for the user.
  """
  @spec suggest_correlations(String.t(), String.t(), map()) :: [{String.t(), String.t()}]
  def suggest_correlations(field_name, value, scope) do
    user_id = scope.user.id

    pattern = {"corr", user_id, field_name, value, :_, :_}

    :ets.match_object(:field_suggestions, {pattern, :_})
    |> Enum.filter(fn {_key, count} -> count >= 3 end)
    |> Enum.map(fn {{_, _uid, _fa, _va, field_b, val_b}, _count} -> {field_b, val_b} end)
  rescue
    e ->
      Logger.error("FieldSuggester.suggest_correlations error: #{inspect(e)}")
      []
  end

  @doc """
  Record field values from a successful import batch.
  Updates freq and correlation counters in ETS (non-blocking via cast).
  """
  @spec record_import([map()], map()) :: :ok
  def record_import(entries, scope) do
    GenServer.cast(__MODULE__, {:record_import, entries, scope})
  rescue
    e ->
      Logger.error("FieldSuggester.record_import error: #{inspect(e)}")
      :ok
  end

  # ===== GenServer Callbacks =====

  @impl true
  def init(_opts) do
    :ets.new(
      :field_suggestions,
      [:set, :named_table, :public, {:read_concurrency, true}]
    )

    Logger.info("FieldSuggester initialized")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:record_import, entries, scope}, state) do
    user_id = scope.user.id
    now = DateTime.utc_now()

    Enum.each(entries, fn entry ->
      type = to_string(entry[:type] || entry["type"] || "")
      attrs = entry[:attrs] || entry["attrs"] || %{}

      fields = Map.get(@tracked_fields, type, [])

      # Collect all (field, value) pairs for this entry
      field_values =
        Enum.flat_map(fields, fn field ->
          value = Map.get(attrs, field) || Map.get(attrs, String.to_atom(field))

          case value do
            nil -> []
            v when is_binary(v) -> [{field, v}]
            v when is_atom(v) -> [{field, Atom.to_string(v)}]
            _ -> []
          end
        end)

      # Update frequency counters
      Enum.each(field_values, fn {field, value} ->
        key = {"freq", user_id, field, value}

        case :ets.lookup(:field_suggestions, key) do
          [{^key, {count, _last}}] ->
            :ets.insert(:field_suggestions, {key, {count + 1, now}})

          [] ->
            :ets.insert(:field_suggestions, {key, {1, now}})
        end
      end)

      # Update correlation counters for all pairs within the same entry
      for {field_a, val_a} <- field_values,
          {field_b, val_b} <- field_values,
          field_a != field_b do
        corr_key = {"corr", user_id, field_a, val_a, field_b, val_b}

        case :ets.lookup(:field_suggestions, corr_key) do
          [{^corr_key, count}] ->
            :ets.insert(:field_suggestions, {corr_key, count + 1})

          [] ->
            :ets.insert(:field_suggestions, {corr_key, 1})
        end
      end
    end)

    {:noreply, state}
  rescue
    e ->
      Logger.error("FieldSuggester handle_cast error: #{inspect(e)}")
      {:noreply, state}
  end

  # ===== Private Helpers =====

  defp lookup_freq_entries(user_id, field_name) do
    pattern = {{"freq", user_id, field_name, :_}, :_}

    :ets.match_object(:field_suggestions, pattern)
    |> Enum.map(fn {{_, _uid, _field, value}, {count, last_used_at}} ->
      {count, last_used_at, value}
    end)
  rescue
    _e -> []
  end

  defp longest_common_prefix([single]) when is_binary(single), do: single

  defp longest_common_prefix([first | rest]) when is_binary(first) do
    Enum.reduce(rest, first, fn str, acc ->
      common_prefix(acc, str)
    end)
  end

  defp common_prefix(a, b) do
    a_chars = String.graphemes(a)
    b_chars = String.graphemes(b)

    a_chars
    |> Enum.zip(b_chars)
    |> Enum.take_while(fn {ca, cb} -> ca == cb end)
    |> Enum.map(fn {c, _} -> c end)
    |> Enum.join()
  end
end
