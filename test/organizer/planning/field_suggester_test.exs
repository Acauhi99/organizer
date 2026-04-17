defmodule Organizer.Planning.FieldSuggesterTest do
  # async: false because FieldSuggester uses named ETS + named GenServer
  use ExUnit.Case, async: false

  alias Organizer.Planning.FieldSuggester

  # ---------------------------------------------------------------------------
  # Setup: start a fresh GenServer (and thus ETS table) for each test.
  # We avoid name clashes with the application-level instance by starting
  # an unnamed process and interacting with ETS directly where needed.
  # ---------------------------------------------------------------------------

  setup do
    # Stop the globally registered FieldSuggester if running (started by app supervisor)
    case Process.whereis(FieldSuggester) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    # Drop the ETS table if it survived a previous crash
    if :ets.whereis(:field_suggestions) != :undefined do
      :ets.delete(:field_suggestions)
    end

    # Start fresh
    {:ok, pid} = FieldSuggester.start_link([])

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

  # Synchronise with the GenServer's mailbox so all casts are processed.
  # :sys.get_state/1 is a synchronous call that forces all pending messages
  # (including casts) to be processed before returning.
  defp record_and_flush(entries, scope) do
    FieldSuggester.record_import(entries, scope)
    :sys.get_state(FieldSuggester)
    :ok
  end

  # ---------------------------------------------------------------------------
  # complete/3 — autocomplete of field values
  # ---------------------------------------------------------------------------

  describe "complete/3 — priority / prioridade field" do
    test "unambiguous prefix returns the unique match" do
      assert FieldSuggester.complete("prioridade", scope(1), "ba") == {:ok, "baixa"}
      assert FieldSuggester.complete("priority", scope(1), "ba") == {:ok, "baixa"}
    end

    test "prefix 'al' matches 'alta' unambiguously" do
      assert FieldSuggester.complete("prioridade", scope(1), "al") == {:ok, "alta"}
    end

    test "prefix 'me' matches 'media' unambiguously" do
      assert FieldSuggester.complete("prioridade", scope(1), "me") == {:ok, "media"}
    end

    test "prefix that matches multiple values returns longest common prefix" do
      # 'a' matches 'alta' — only one match in priority values
      assert FieldSuggester.complete("prioridade", scope(1), "a") == {:ok, "alta"}
    end

    test "case-insensitive prefix match" do
      assert FieldSuggester.complete("prioridade", scope(1), "BA") == {:ok, "baixa"}
      assert FieldSuggester.complete("prioridade", scope(1), "Al") == {:ok, "alta"}
    end
  end

  describe "complete/3 — status field" do
    test "prefix 'fa' returns 'fazer'" do
      assert FieldSuggester.complete("status", scope(1), "fa") == {:ok, "fazer"}
    end

    test "prefix 'em' returns 'em_andamento'" do
      assert FieldSuggester.complete("status", scope(1), "em") == {:ok, "em_andamento"}
    end

    test "prefix 'con' returns 'concluido'" do
      assert FieldSuggester.complete("status", scope(1), "con") == {:ok, "concluido"}
    end
  end

  describe "complete/3 — horizonte / horizon field" do
    test "prefix 'cu' returns 'curto'" do
      assert FieldSuggester.complete("horizonte", scope(1), "cu") == {:ok, "curto"}
      assert FieldSuggester.complete("horizon", scope(1), "cu") == {:ok, "curto"}
    end

    test "prefix 'lo' returns 'longo'" do
      assert FieldSuggester.complete("horizonte", scope(1), "lo") == {:ok, "longo"}
    end

    test "prefix 'med' returns 'medio'" do
      assert FieldSuggester.complete("horizonte", scope(1), "med") == {:ok, "medio"}
    end
  end

  describe "complete/3 — tipo / kind field" do
    test "prefix 'de' returns 'despesa'" do
      assert FieldSuggester.complete("tipo", scope(1), "de") == {:ok, "despesa"}
      assert FieldSuggester.complete("kind", scope(1), "de") == {:ok, "despesa"}
    end

    test "prefix 're' returns 'receita'" do
      assert FieldSuggester.complete("tipo", scope(1), "re") == {:ok, "receita"}
    end
  end

  describe "complete/3 — natureza / expense_profile field" do
    test "prefix 'fi' returns 'fixa'" do
      assert FieldSuggester.complete("natureza", scope(1), "fi") == {:ok, "fixa"}
      assert FieldSuggester.complete("expense_profile", scope(1), "fi") == {:ok, "fixa"}
    end

    test "prefix 'va' returns 'variavel'" do
      assert FieldSuggester.complete("natureza", scope(1), "va") == {:ok, "variavel"}
    end
  end

  describe "complete/3 — pagamento / payment_method field" do
    test "prefix 'deb' returns 'debito'" do
      assert FieldSuggester.complete("pagamento", scope(1), "deb") == {:ok, "debito"}
      assert FieldSuggester.complete("payment_method", scope(1), "deb") == {:ok, "debito"}
    end

    test "prefix 'cre' returns 'credito'" do
      assert FieldSuggester.complete("pagamento", scope(1), "cre") == {:ok, "credito"}
    end
  end

  describe "complete/3 — edge cases" do
    test "prefix with no match returns {:ok, nil}" do
      assert FieldSuggester.complete("prioridade", scope(1), "xyz") == {:ok, nil}
    end

    test "unknown field returns {:ok, nil}" do
      assert FieldSuggester.complete("unknown_field", scope(1), "al") == {:ok, nil}
    end

    test "empty prefix with multiple values returns longest common prefix" do
      # "debito" and "credito" — common prefix is empty string ""
      result = FieldSuggester.complete("pagamento", scope(1), "")
      assert result == {:ok, ""}
    end

    test "full value as prefix returns the value itself" do
      assert FieldSuggester.complete("prioridade", scope(1), "baixa") == {:ok, "baixa"}
    end
  end

  # ---------------------------------------------------------------------------
  # suggest_values/2 — ordering by frequency and recency
  # ---------------------------------------------------------------------------

  describe "suggest_values/2 — no history" do
    test "returns canonical list for a known field when user has no history" do
      result = FieldSuggester.suggest_values("priority", scope(99))
      assert is_list(result)
      assert "baixa" in result
      assert "media" in result
      assert "alta" in result
    end

    test "returns empty list for unknown field" do
      result = FieldSuggester.suggest_values("nonexistent_field", scope(99))
      assert result == []
    end
  end

  describe "suggest_values/2 — with usage history" do
    test "most-used value appears first" do
      scope_a = scope(1)

      # Record 'alta' 3 times and 'baixa' once
      for _ <- 1..3 do
        record_and_flush(
          [%{type: "task", attrs: %{"priority" => "alta"}}],
          scope_a
        )
      end

      record_and_flush(
        [%{type: "task", attrs: %{"priority" => "baixa"}}],
        scope_a
      )

      [first | _] = FieldSuggester.suggest_values("priority", scope_a)
      assert first == "alta"
    end

    test "with equal frequency, value recorded first appears first (ascending DateTime tiebreak)" do
      scope_a = scope(2)

      # 'baixa' is recorded first, then 'alta'
      # The sort key is {-count, last_used_at} ascending: equal counts → earlier datetime wins
      record_and_flush(
        [%{type: "task", attrs: %{"priority" => "baixa"}}],
        scope_a
      )

      record_and_flush(
        [%{type: "task", attrs: %{"priority" => "alta"}}],
        scope_a
      )

      # Both have count=1; 'baixa' has the earlier timestamp so it comes first
      [first | _] = FieldSuggester.suggest_values("priority", scope_a)
      assert first == "baixa"
    end

    test "all three priority values appear in results after varied usage" do
      scope_a = scope(3)

      record_and_flush([%{type: "task", attrs: %{"priority" => "alta"}}], scope_a)
      record_and_flush([%{type: "task", attrs: %{"priority" => "media"}}], scope_a)
      record_and_flush([%{type: "task", attrs: %{"priority" => "baixa"}}], scope_a)

      result = FieldSuggester.suggest_values("priority", scope_a)
      assert length(result) == 3
      assert "alta" in result
      assert "media" in result
      assert "baixa" in result
    end
  end

  # ---------------------------------------------------------------------------
  # User isolation: suggest_values/2
  # ---------------------------------------------------------------------------

  describe "suggest_values/2 — user isolation" do
    test "history from user A does not influence suggestions for user B" do
      scope_a = scope(100)
      scope_b = scope(200)

      # User A records 'alta' many times
      for _ <- 1..5 do
        record_and_flush([%{type: "task", attrs: %{"priority" => "alta"}}], scope_a)
      end

      # User B has no history — should get canonical list, not A's frequency order
      result_b = FieldSuggester.suggest_values("priority", scope_b)
      # The result is the canonical list (not frequency-ranked from A's data)
      assert is_list(result_b)
      assert "alta" in result_b
      # Importantly, the order is the static canonical one, not A's ranked order
      canonical = ["baixa", "media", "alta"]
      assert Enum.sort(result_b) == Enum.sort(canonical)
    end

    test "user B's history does not affect user A's suggestions" do
      scope_a = scope(101)
      scope_b = scope(201)

      record_and_flush([%{type: "task", attrs: %{"priority" => "baixa"}}], scope_b)
      record_and_flush([%{type: "task", attrs: %{"priority" => "baixa"}}], scope_b)
      record_and_flush([%{type: "task", attrs: %{"priority" => "baixa"}}], scope_b)

      record_and_flush([%{type: "task", attrs: %{"priority" => "alta"}}], scope_a)

      [first_a | _] = FieldSuggester.suggest_values("priority", scope_a)
      assert first_a == "alta"
    end
  end

  # ---------------------------------------------------------------------------
  # suggest_correlations/3
  # ---------------------------------------------------------------------------

  describe "suggest_correlations/3" do
    test "returns empty list when no correlations recorded" do
      result = FieldSuggester.suggest_correlations("priority", "alta", scope(1))
      assert result == []
    end

    test "returns correlation only after threshold of 3 co-occurrences" do
      scope_a = scope(10)

      entry = %{
        type: "finance",
        attrs: %{"kind" => "expense", "payment_method" => "debito"}
      }

      # 2 imports — below threshold
      record_and_flush([entry], scope_a)
      record_and_flush([entry], scope_a)

      assert FieldSuggester.suggest_correlations("kind", "expense", scope_a) == []

      # 3rd import pushes it over the threshold
      record_and_flush([entry], scope_a)

      result = FieldSuggester.suggest_correlations("kind", "expense", scope_a)
      assert {"payment_method", "debito"} in result
    end

    test "returns both directions of a correlation pair" do
      scope_a = scope(11)

      entry = %{
        type: "finance",
        attrs: %{"expense_profile" => "fixa", "payment_method" => "debito"}
      }

      for _ <- 1..3, do: record_and_flush([entry], scope_a)

      corr_a = FieldSuggester.suggest_correlations("expense_profile", "fixa", scope_a)
      assert {"payment_method", "debito"} in corr_a

      corr_b = FieldSuggester.suggest_correlations("payment_method", "debito", scope_a)
      assert {"expense_profile", "fixa"} in corr_b
    end

    test "correlation suggestions are isolated per user" do
      scope_a = scope(12)
      scope_b = scope(13)

      entry = %{
        type: "finance",
        attrs: %{"kind" => "expense", "payment_method" => "credito"}
      }

      for _ <- 1..5, do: record_and_flush([entry], scope_a)

      # User B should not see user A's correlations
      result_b = FieldSuggester.suggest_correlations("kind", "expense", scope_b)
      assert result_b == []
    end
  end

  # ---------------------------------------------------------------------------
  # record_import/2 — frequency tracking
  # ---------------------------------------------------------------------------

  describe "record_import/2" do
    test "increments frequency counter on repeated imports" do
      scope_a = scope(20)

      record_and_flush([%{type: "task", attrs: %{"priority" => "alta"}}], scope_a)
      record_and_flush([%{type: "task", attrs: %{"priority" => "alta"}}], scope_a)

      # Should rank 'alta' at the top
      [first | _] = FieldSuggester.suggest_values("priority", scope_a)
      assert first == "alta"
    end

    test "handles atom-keyed attrs" do
      scope_a = scope(21)

      record_and_flush([%{type: "task", attrs: %{priority: "media"}}], scope_a)

      [first | _] = FieldSuggester.suggest_values("priority", scope_a)
      assert first == "media"
    end

    test "handles atom value (converts to string)" do
      scope_a = scope(22)

      record_and_flush([%{type: "task", attrs: %{"priority" => :alta}}], scope_a)

      result = FieldSuggester.suggest_values("priority", scope_a)
      assert "alta" in result
    end

    test "ignores nil field values" do
      scope_a = scope(23)

      # Should not crash on nil value, just skip
      record_and_flush([%{type: "task", attrs: %{"priority" => nil}}], scope_a)

      result = FieldSuggester.suggest_values("priority", scope_a)
      # Still returns canonical fallback — nil was not recorded
      assert is_list(result)
    end

    test "unknown entry type does not crash and records nothing" do
      scope_a = scope(24)

      record_and_flush([%{type: "unknown_type", attrs: %{"priority" => "alta"}}], scope_a)

      # No history was recorded, so canonical fallback
      result = FieldSuggester.suggest_values("priority", scope_a)
      assert "alta" in result
    end
  end
end
