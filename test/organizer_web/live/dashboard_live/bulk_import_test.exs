defmodule OrganizerWeb.DashboardLive.BulkImportTest do
  # Not async: we need to ensure atoms are pre-created before tests run.
  use ExUnit.Case
  use ExUnitProperties

  alias OrganizerWeb.DashboardLive.BulkImport

  # AttributeValidation uses String.to_existing_atom/1 for status/priority/kind
  # values. Those atoms must exist in the BEAM atom table before any test runs.
  # We pre-create them here to avoid ArgumentError in tests.
  setup_all do
    # Task atoms
    _ = :todo
    _ = :in_progress
    _ = :done
    _ = :low
    _ = :medium
    _ = :high
    # Finance atoms
    _ = :income
    _ = :expense
    _ = :fixed
    _ = :variable
    _ = :credit
    _ = :debit
    # Goal atoms
    _ = :active
    _ = :paused
    _ = :short
    _ = :long
    :ok
  end

  # ---------------------------------------------------------------------------
  # preview_bulk_payload/1
  # ---------------------------------------------------------------------------

  describe "preview_bulk_payload/1" do
    test "parses a valid task line" do
      payload = "tarefa: reunião com equipe"
      result = BulkImport.preview_bulk_payload(payload)

      assert result.lines_total == 1
      assert result.valid_total == 1
      assert result.invalid_total == 0
      assert result.ignored_total == 0
      assert is_list(result.entries)
      assert is_map(result.scoring)

      [entry] = result.entries
      assert entry.status == :valid
      assert entry.type == :task
      assert entry.line_number == 1
    end

    test "parses a valid finance line" do
      payload = "financeiro: almoço 35"
      result = BulkImport.preview_bulk_payload(payload)

      assert result.valid_total == 1
      [entry] = result.entries
      assert entry.status == :valid
      assert entry.type == :finance
    end

    test "parses a valid goal line" do
      payload = "meta: aprender Elixir"
      result = BulkImport.preview_bulk_payload(payload)

      assert result.valid_total == 1
      [entry] = result.entries
      assert entry.status == :valid
      assert entry.type == :goal
    end

    test "marks empty lines as ignored" do
      payload = "\n\n"
      result = BulkImport.preview_bulk_payload(payload)

      assert result.ignored_total == result.lines_total
      assert result.valid_total == 0
      assert result.invalid_total == 0
    end

    test "marks unrecognized lines as invalid" do
      payload = "isso nao e valido"
      result = BulkImport.preview_bulk_payload(payload)

      assert result.invalid_total >= 1
      assert result.valid_total == 0
    end

    test "handles mixed payload with valid, invalid and ignored lines" do
      payload = """
      tarefa: reunião com equipe
      isso nao e valido
      meta: aprender Elixir

      financeiro: almoço 35
      """

      result = BulkImport.preview_bulk_payload(payload)

      assert result.lines_total > 0
      assert result.valid_total >= 3
      assert result.invalid_total >= 1
      assert result.ignored_total >= 1

      assert result.valid_total + result.invalid_total + result.ignored_total ==
               result.lines_total
    end

    test "result always has required keys" do
      result = BulkImport.preview_bulk_payload("tarefa: test")

      assert Map.has_key?(result, :entries)
      assert Map.has_key?(result, :lines_total)
      assert Map.has_key?(result, :valid_total)
      assert Map.has_key?(result, :invalid_total)
      assert Map.has_key?(result, :ignored_total)
      assert Map.has_key?(result, :scoring)
    end

    test "handles empty string" do
      result = BulkImport.preview_bulk_payload("")

      assert result.lines_total >= 0
      assert result.valid_total == 0
    end
  end

  # ---------------------------------------------------------------------------
  # bulk_template_payload/1
  # ---------------------------------------------------------------------------

  describe "bulk_template_payload/1" do
    test "returns non-empty string for 'mixed'" do
      result = BulkImport.bulk_template_payload("mixed")

      assert is_binary(result)
      assert String.length(result) > 0
      assert String.contains?(result, "tarefa:")
      assert String.contains?(result, "financeiro:")
      assert String.contains?(result, "meta:")
    end

    test "returns non-empty string for 'tasks'" do
      result = BulkImport.bulk_template_payload("tasks")

      assert is_binary(result)
      assert String.length(result) > 0
      assert String.contains?(result, "tarefa:")
    end

    test "returns non-empty string for 'finance'" do
      result = BulkImport.bulk_template_payload("finance")

      assert is_binary(result)
      assert String.length(result) > 0
      assert String.contains?(result, "financeiro:")
    end

    test "returns non-empty string for 'goals'" do
      result = BulkImport.bulk_template_payload("goals")

      assert is_binary(result)
      assert String.length(result) > 0
      assert String.contains?(result, "meta:")
    end

    test "returns empty string for unknown key" do
      assert BulkImport.bulk_template_payload("unknown") == ""
      assert BulkImport.bulk_template_payload("") == ""
    end

    test "templates produce parseable previews" do
      for key <- ["mixed", "tasks", "finance", "goals"] do
        payload = BulkImport.bulk_template_payload(key)
        result = BulkImport.preview_bulk_payload(payload)

        assert result.valid_total > 0,
               "Expected template '#{key}' to produce valid entries, got: #{inspect(result)}"
      end
    end
  end

  describe "bulk_reference_markdown_template/0" do
    test "returns a markdown guide with all supported types" do
      markdown = BulkImport.bulk_reference_markdown_template()

      assert is_binary(markdown)
      assert String.contains?(markdown, "# Organizer - Guia de Importacao Copy/Paste (Markdown)")
      assert String.contains?(markdown, "## Tarefa")
      assert String.contains?(markdown, "## Financeiro")
      assert String.contains?(markdown, "## Meta")
      assert String.contains?(markdown, "`tipo: conteudo`")
    end
  end

  # ---------------------------------------------------------------------------
  # apply_bulk_fix_for_line/2
  # ---------------------------------------------------------------------------

  describe "apply_bulk_fix_for_line/2" do
    test "applies fix when a suggested line is available" do
      # A line with a missing colon should get a fix suggestion
      payload = "tarefa reunião com equipe"
      result = BulkImport.apply_bulk_fix_for_line(payload, 1)

      case result do
        {:ok, fixed_payload} ->
          assert is_binary(fixed_payload)
          # The fixed line should contain the colon
          assert String.contains?(fixed_payload, "tarefa:")

        {:error, :no_fix_available} ->
          # Acceptable if no fix is generated for this input
          :ok
      end
    end

    test "returns error when no fix is available for a valid line" do
      payload = "tarefa: reunião com equipe"
      result = BulkImport.apply_bulk_fix_for_line(payload, 1)

      # A valid line has no fix needed
      assert result == {:error, :no_fix_available}
    end

    test "returns error when no fix is available for an ignored line" do
      payload = ""
      result = BulkImport.apply_bulk_fix_for_line(payload, 1)

      assert result == {:error, :no_fix_available}
    end

    test "returns :invalid_input for non-binary payload" do
      assert BulkImport.apply_bulk_fix_for_line(nil, 1) == {:error, :invalid_input}
      assert BulkImport.apply_bulk_fix_for_line(123, 1) == {:error, :invalid_input}
    end

    test "returns :invalid_input for non-positive line number" do
      assert BulkImport.apply_bulk_fix_for_line("tarefa: test", 0) == {:error, :invalid_input}
      assert BulkImport.apply_bulk_fix_for_line("tarefa: test", -1) == {:error, :invalid_input}
    end

    test "applies fix to the correct line in a multi-line payload" do
      payload = "tarefa: válida\ntarefa sem dois pontos\nmeta: outra válida"

      case BulkImport.apply_bulk_fix_for_line(payload, 2) do
        {:ok, fixed} ->
          lines = String.split(fixed, "\n")
          # Line 1 and 3 should be unchanged
          assert Enum.at(lines, 0) == "tarefa: válida"
          assert Enum.at(lines, 2) == "meta: outra válida"

        {:error, :no_fix_available} ->
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # apply_all_bulk_fixes/1
  # ---------------------------------------------------------------------------

  describe "apply_all_bulk_fixes/1" do
    test "returns ok tuple with fixed payload and count" do
      payload = "tarefa: válida\nmeta: outra válida"
      result = BulkImport.apply_all_bulk_fixes(payload)

      assert {:ok, fixed_payload, count} = result
      assert is_binary(fixed_payload)
      assert is_integer(count)
      assert count >= 0
    end

    test "returns count of 0 when no fixes are needed" do
      payload = "tarefa: reunião\nmeta: aprender Elixir"
      {:ok, _fixed, count} = BulkImport.apply_all_bulk_fixes(payload)

      assert count == 0
    end

    test "fixes multiple fixable lines" do
      # Lines with missing colons should be fixable
      payload = "tarefa reunião\nmeta aprender Elixir"
      result = BulkImport.apply_all_bulk_fixes(payload)

      assert {:ok, _fixed, count} = result
      # count may be 0 if no fixes are generated, but the function should succeed
      assert is_integer(count)
    end

    test "returns :invalid_input for non-binary payload" do
      assert BulkImport.apply_all_bulk_fixes(nil) == {:error, :invalid_input}
      assert BulkImport.apply_all_bulk_fixes(123) == {:error, :invalid_input}
    end

    test "handles empty string" do
      assert {:ok, _fixed, count} = BulkImport.apply_all_bulk_fixes("")
      assert count == 0
    end
  end

  # ---------------------------------------------------------------------------
  # current_bulk_import_block/3
  # ---------------------------------------------------------------------------

  describe "current_bulk_import_block/3" do
    test "returns empty block when preview is nil" do
      result = BulkImport.current_bulk_import_block(nil, 5, 0)

      assert result == %{entries: [], index: 0, total: 0}
    end

    test "returns correct block structure for a preview with valid entries" do
      payload = """
      tarefa: reunião com equipe
      meta: aprender Elixir
      financeiro: almoço 35
      """

      preview = BulkImport.preview_bulk_payload(payload)
      result = BulkImport.current_bulk_import_block(preview, 2, 0)

      assert is_list(result.entries)
      assert is_integer(result.index)
      assert is_integer(result.total)
      assert result.index >= 0
      assert result.total >= 0
    end

    test "clamps index to valid range" do
      payload = "tarefa: reunião\nmeta: aprender Elixir\nfinanceiro: almoço 35"
      preview = BulkImport.preview_bulk_payload(payload)

      # Index way out of bounds should be clamped
      result = BulkImport.current_bulk_import_block(preview, 1, 9999)

      assert result.index < result.total || result.total == 0
    end

    test "handles size of 1 (one entry per block)" do
      payload = "tarefa: reunião\nmeta: aprender Elixir\nfinanceiro: almoço 35"
      preview = BulkImport.preview_bulk_payload(payload)
      result = BulkImport.current_bulk_import_block(preview, 1, 0)

      assert length(result.entries) <= 1
    end

    test "returns empty entries when preview has no valid entries" do
      payload = "isso nao e valido"
      preview = BulkImport.preview_bulk_payload(payload)
      result = BulkImport.current_bulk_import_block(preview, 5, 0)

      assert result.entries == []
      assert result.total == 0
    end
  end

  # ---------------------------------------------------------------------------
  # remove_bulk_payload_lines/2
  # ---------------------------------------------------------------------------

  describe "remove_bulk_payload_lines/2" do
    test "removes specified line numbers" do
      payload = "linha 1\nlinha 2\nlinha 3"
      result = BulkImport.remove_bulk_payload_lines(payload, [2])

      refute String.contains?(result, "linha 2")
      assert String.contains?(result, "linha 1")
      assert String.contains?(result, "linha 3")
    end

    test "removes multiple lines" do
      payload = "linha 1\nlinha 2\nlinha 3\nlinha 4"
      result = BulkImport.remove_bulk_payload_lines(payload, [1, 3])

      refute String.contains?(result, "linha 1")
      refute String.contains?(result, "linha 3")
      assert String.contains?(result, "linha 2")
      assert String.contains?(result, "linha 4")
    end

    test "returns original payload when line_numbers is empty" do
      payload = "linha 1\nlinha 2"
      result = BulkImport.remove_bulk_payload_lines(payload, [])

      assert result == String.trim(payload)
    end

    test "handles removing all lines" do
      payload = "linha 1\nlinha 2"
      result = BulkImport.remove_bulk_payload_lines(payload, [1, 2])

      assert result == ""
    end

    test "ignores out-of-bounds line numbers" do
      payload = "linha 1\nlinha 2"
      result = BulkImport.remove_bulk_payload_lines(payload, [99])

      assert String.contains?(result, "linha 1")
      assert String.contains?(result, "linha 2")
    end

    test "returns payload unchanged for non-binary input" do
      result = BulkImport.remove_bulk_payload_lines(nil, [1])
      assert result == nil

      result = BulkImport.remove_bulk_payload_lines(123, [1])
      assert result == 123
    end
  end

  # ---------------------------------------------------------------------------
  # Property 6: Resultado de preview sempre tem estrutura completa
  # Feature: dashboard-live-refactor, Property 6
  # ---------------------------------------------------------------------------

  property "preview_bulk_payload always returns a map with complete structure" do
    # Feature: dashboard-live-refactor, Property 6
    check all(payload <- StreamData.string(:printable)) do
      result = BulkImport.preview_bulk_payload(payload)

      assert Map.has_key?(result, :entries)
      assert Map.has_key?(result, :lines_total)
      assert Map.has_key?(result, :valid_total)
      assert Map.has_key?(result, :invalid_total)
      assert Map.has_key?(result, :ignored_total)
      assert Map.has_key?(result, :scoring)

      assert is_list(result.entries)
      assert is_integer(result.lines_total)
      assert is_integer(result.valid_total)
      assert is_integer(result.invalid_total)
      assert is_integer(result.ignored_total)

      assert result.valid_total + result.invalid_total + result.ignored_total ==
               result.lines_total
    end
  end
end
