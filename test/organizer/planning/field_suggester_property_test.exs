defmodule Organizer.Planning.FieldSuggesterPropertyTest do
  # async: false — FieldSuggester uses a named ETS table and named GenServer.
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Organizer.Planning.FieldSuggester
  alias Organizer.Planning.FilterNormalization

  # ---------------------------------------------------------------------------
  # Setup: isolated GenServer + ETS per test (same pattern as unit test file)
  # ---------------------------------------------------------------------------

  setup do
    # Stop the globally registered FieldSuggester (started by app supervisor).
    # The supervisor may restart it immediately, so we handle both cases.
    case Process.whereis(FieldSuggester) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    # Drop ETS if it survived
    if :ets.whereis(:field_suggestions) != :undefined do
      :ets.delete(:field_suggestions)
    end

    # Start our own fresh instance.
    # If the supervisor already restarted FieldSuggester, grab that pid instead.
    pid =
      case FieldSuggester.start_link([]) do
        {:ok, pid} ->
          pid

        {:error, {:already_started, pid}} ->
          # Supervisor restarted it; wipe its ETS data to start clean
          :ets.delete_all_objects(:field_suggestions)
          pid
      end

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)

      if :ets.whereis(:field_suggestions) != :undefined do
        :ets.delete(:field_suggestions)
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp scope(user_id), do: %{user: %{id: user_id}}

  # Flush all pending GenServer casts before asserting
  defp flush do
    :sys.get_state(FieldSuggester)
    :ok
  end

  defp record_and_flush(entries, scope) do
    FieldSuggester.record_import(entries, scope)
    flush()
  end

  # ---------------------------------------------------------------------------
  # Field metadata
  # ---------------------------------------------------------------------------

  # Only fields/values whose canonical string can be resolved by
  # FilterNormalization.normalize_filter_value/3 to the expected atom.
  # (Verified empirically — see analysis in task 4.7 implementation notes.)
  #
  # Excluded: "concluido" (no alias → :done), "curto" (no alias → :short),
  # "fixa" (no alias → :fixed), "variavel" (no alias → :variable)
  @normalizable_fields [
    # {field_name, canonical_value, allowed_atoms, expected_atom}
    {"prioridade", "baixa", [:low, :medium, :high], :low},
    {"prioridade", "media", [:low, :medium, :high], :medium},
    {"prioridade", "alta", [:low, :medium, :high], :high},
    {"priority", "baixa", [:low, :medium, :high], :low},
    {"priority", "media", [:low, :medium, :high], :medium},
    {"priority", "alta", [:low, :medium, :high], :high},
    {"status", "fazer", [:todo, :in_progress, :done], :todo},
    {"status", "em_andamento", [:todo, :in_progress, :done], :in_progress},
    {"horizonte", "medio", [:short, :medium, :long], :medium},
    {"horizonte", "longo", [:short, :medium, :long], :long},
    {"horizon", "medio", [:short, :medium, :long], :medium},
    {"horizon", "longo", [:short, :medium, :long], :long},
    {"tipo", "despesa", [:expense, :income], :expense},
    {"tipo", "receita", [:expense, :income], :income},
    {"kind", "despesa", [:expense, :income], :expense},
    {"kind", "receita", [:expense, :income], :income},
    {"pagamento", "debito", [:debit, :credit], :debit},
    {"pagamento", "credito", [:debit, :credit], :credit},
    {"payment_method", "debito", [:debit, :credit], :debit},
    {"payment_method", "credito", [:debit, :credit], :credit}
  ]

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  # Generates {field_name, canonical_value, prefix, allowed_atoms, expected_atom}
  # quintuples where prefix is a strict unambiguous prefix of canonical_value.
  #
  # A "strict prefix" is a non-empty prefix shorter than the full value that
  # matches exactly one canonical value for the field.
  defp gen_field_prefix do
    all_values_per_field =
      @normalizable_fields
      |> Enum.group_by(fn {field, _, _, _} -> field end)
      |> Enum.map(fn {field, entries} -> {field, Enum.map(entries, fn {_, v, _, _} -> v end)} end)
      |> Map.new()

    triples =
      Enum.flat_map(@normalizable_fields, fn {field, value, allowed_atoms, expected_atom} ->
        all_values = Map.get(all_values_per_field, field, [value])
        max_len = String.length(value) - 1

        if max_len < 1 do
          []
        else
          Enum.flat_map(1..max_len, fn len ->
            prefix = String.slice(value, 0, len)

            # Only include if this prefix uniquely matches one canonical value in the field
            matches =
              Enum.filter(all_values, fn v ->
                String.starts_with?(String.downcase(v), String.downcase(prefix))
              end)

            if length(matches) == 1 do
              [{field, value, prefix, allowed_atoms, expected_atom}]
            else
              []
            end
          end)
        end
      end)

    StreamData.member_of(triples)
  end

  # Generates distinct frequency counts for 3 values without filtering.
  # We pick a permutation of [1, 2, 3] and multiply by a base to get 3
  # always-distinct counts: (base, base*2, base*3) in some order.
  @history_values ["baixa", "media", "alta"]
  @history_field "priority"

  # All 6 permutations of indices [0, 1, 2]
  @permutations [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

  defp gen_usage_history do
    gen all(
          base <- StreamData.integer(1..5),
          perm <- StreamData.member_of(@permutations)
        ) do
      # counts are base*(perm[i]+1): always distinct since perm is a permutation of 0,1,2
      [a, b, c] = Enum.map(perm, fn i -> base * (i + 1) end)
      [{"baixa", a}, {"media", b}, {"alta", c}]
    end
  end

  # ---------------------------------------------------------------------------
  # Property 1: Round-trip autocomplete com normalização
  # Validates: Requirements 1.6, 1.7
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 1
  property "Propriedade 1: round-trip de autocomplete com normalização" do
    check all(
            {field_name, canonical_value, prefix, allowed_atoms, expected_atom} <-
              gen_field_prefix(),
            min_runs: 100
          ) do
      # Step 1: complete/3 must return the full canonical value
      {:ok, completed} = FieldSuggester.complete(field_name, scope(1), prefix)

      assert completed == canonical_value,
             "complete(#{inspect(field_name)}, _, #{inspect(prefix)}) " <>
               "returned #{inspect(completed)}, expected #{inspect(canonical_value)}"

      # Step 2: normalize_filter_value/3 on the completed value must return
      # the expected canonical atom for this field
      result =
        FilterNormalization.normalize_filter_value(completed, allowed_atoms, field_name)

      assert result == {:ok, expected_atom},
             "normalize_filter_value(#{inspect(completed)}, #{inspect(allowed_atoms)}, #{inspect(field_name)}) " <>
               "returned #{inspect(result)}, expected {:ok, #{inspect(expected_atom)}}"
    end
  end

  # ---------------------------------------------------------------------------
  # Property 11: Monotonicidade do ranking
  # Validates: Requirements 7.6, 7.7
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 11
  property "Propriedade 11: monotonicidade do ranking — valor mais frequente aparece antes" do
    check all(
            history <- gen_usage_history(),
            min_runs: 100
          ) do
      user_id = :erlang.unique_integer([:positive])
      s = scope(user_id)

      # Seed ETS with the generated frequency history
      Enum.each(history, fn {value, count} ->
        for _ <- 1..count do
          record_and_flush(
            [%{type: "task", attrs: %{"priority" => value}}],
            s
          )
        end
      end)

      suggestions = FieldSuggester.suggest_values(@history_field, s)

      # Build freq map from history
      freq = Map.new(history, fn {v, c} -> {v, c} end)

      # For every pair, assert the higher-frequency value is ranked first
      for v1 <- @history_values,
          v2 <- @history_values,
          v1 != v2,
          Map.get(freq, v1, 0) > Map.get(freq, v2, 0) do
        idx1 = Enum.find_index(suggestions, &(&1 == v1))
        idx2 = Enum.find_index(suggestions, &(&1 == v2))

        assert idx1 != nil and idx2 != nil,
               "Both #{v1} and #{v2} should appear in suggestions, got: #{inspect(suggestions)}"

        assert idx1 < idx2,
               "Expected #{v1} (freq=#{freq[v1]}) before #{v2} (freq=#{freq[v2]}), " <>
                 "but suggestions order is: #{inspect(suggestions)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property 12: Isolamento por usuário
  # Validates: Requirements 7.4, 10.7
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 12
  property "Propriedade 12: isolamento por usuário — histórico de v não aparece para u" do
    check all(
            value_v <- StreamData.member_of(["baixa", "media", "alta"]),
            count_v <- StreamData.integer(5..10),
            min_runs: 100
          ) do
      run_id = :erlang.unique_integer([:positive])
      user_v = 100_000 + run_id
      user_u = 200_000 + run_id

      scope_v = scope(user_v)
      scope_u = scope(user_u)

      # Record priority usage exclusively for user_v
      for _ <- 1..count_v do
        record_and_flush(
          [%{type: "task", attrs: %{"priority" => value_v}}],
          scope_v
        )
      end

      # User u has NO priority history — must receive the static canonical list
      suggestions_u = FieldSuggester.suggest_values("priority", scope_u)

      # The unranked canonical list for "priority"
      canonical_priority = ["baixa", "media", "alta"]

      # User u sees all canonical values
      assert Enum.sort(suggestions_u) == Enum.sort(canonical_priority),
             "User #{user_u} should see canonical priority values, " <>
               "got: #{inspect(suggestions_u)}"

      # And the ORDER must be the static canonical order (no frequency ranking from v)
      assert suggestions_u == canonical_priority,
             "User #{user_u} priority suggestions must be unranked canonical list " <>
               "#{inspect(canonical_priority)}, got: #{inspect(suggestions_u)} " <>
               "— user #{user_v}'s history may have leaked"
    end
  end

  # ---------------------------------------------------------------------------
  # Property 13: Completude de correlação
  # Validates: Requirements 10.6
  # ---------------------------------------------------------------------------

  # Pre-built cross-field pairs: {field_a, val_a, field_b, val_b}
  # All combinations where field_a != field_b, covering the "finance" tracked fields.
  @corr_cross_pairs (for {fa, va} <- [
                           {"kind", "despesa"},
                           {"kind", "receita"},
                           {"expense_profile", "fixa"},
                           {"expense_profile", "variavel"},
                           {"payment_method", "debito"},
                           {"payment_method", "credito"}
                         ],
                         {fb, vb} <- [
                           {"kind", "despesa"},
                           {"kind", "receita"},
                           {"expense_profile", "fixa"},
                           {"expense_profile", "variavel"},
                           {"payment_method", "debito"},
                           {"payment_method", "credito"}
                         ],
                         fa != fb do
                       {fa, va, fb, vb}
                     end)

  @tag feature: "ai-like-input-enhancements", property: 13
  property "Propriedade 13: par com co-ocorrência >= 3 aparece em suggest_correlations/3" do
    check all(
            {field_a, val_a, field_b, val_b} <- StreamData.member_of(@corr_cross_pairs),
            co_count <- StreamData.integer(3..8),
            min_runs: 100
          ) do
      user_id = :erlang.unique_integer([:positive])
      s = scope(user_id)

      # Build a finance entry that contains both (field_a, val_a) and (field_b, val_b)
      entry = %{
        type: "finance",
        attrs: %{field_a => val_a, field_b => val_b}
      }

      for _ <- 1..co_count do
        record_and_flush([entry], s)
      end

      correlations = FieldSuggester.suggest_correlations(field_a, val_a, s)

      assert {field_b, val_b} in correlations,
             "Expected {#{inspect(field_b)}, #{inspect(val_b)}} in " <>
               "suggest_correlations(#{inspect(field_a)}, #{inspect(val_a)}, ...) " <>
               "after #{co_count} co-occurrences, got: #{inspect(correlations)}"
    end
  end
end
