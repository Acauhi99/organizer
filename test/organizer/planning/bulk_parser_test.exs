defmodule Organizer.Planning.BulkParserTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Organizer.Planning.BulkParser

  # Fixed reference date: 2025-01-15, a Wednesday
  @ref ~D[2025-01-15]
  @opts %{reference_date: @ref}

  # ---------------------------------------------------------------------------
  # Req 8.1 / 8.2 — minimum task line with expected defaults
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — minimal task line" do
    test "tarefa: Comprar leite returns valid entry with defaults" do
      entry = BulkParser.parse_line("tarefa: Comprar leite", @opts)

      assert entry.status == :valid
      assert entry.type == :task
      assert entry.attrs["title"] == "Comprar leite"
      assert entry.attrs["status"] == "todo"
      assert entry.attrs["priority"] == "medium"
      refute Map.has_key?(entry.attrs, "due_on")
    end

    test "default status is 'todo'" do
      entry = BulkParser.parse_line("tarefa: Estudar Elixir", @opts)
      assert entry.attrs["status"] == "todo"
    end

    test "default priority is 'medium'" do
      entry = BulkParser.parse_line("tarefa: Estudar Elixir", @opts)
      assert entry.attrs["priority"] == "medium"
    end

    test "default due_on is nil (not present in attrs)" do
      entry = BulkParser.parse_line("tarefa: Estudar Elixir", @opts)
      refute Map.has_key?(entry.attrs, "due_on")
    end

    test "inferred_fields is empty for plain task with no inference" do
      entry = BulkParser.parse_line("tarefa: Comprar leite", @opts)
      assert entry.inferred_fields == []
    end

    test "task alias 'task:' also works" do
      entry = BulkParser.parse_line("task: Buy milk", @opts)
      assert entry.status == :valid
      assert entry.type == :task
    end
  end

  # ---------------------------------------------------------------------------
  # Req 8.5 — minimum goal line with expected defaults
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — minimal goal line" do
    test "meta: Aprender Elixir returns valid entry with defaults" do
      entry = BulkParser.parse_line("meta: Aprender Elixir", @opts)

      assert entry.status == :valid
      assert entry.type == :goal
      assert entry.attrs["title"] == "Aprender Elixir"
      assert entry.attrs["horizon"] == "medium"
      assert entry.attrs["status"] == "active"
      refute Map.has_key?(entry.attrs, "target_value")
    end

    test "default horizon is 'medium'" do
      entry = BulkParser.parse_line("meta: Ler 12 livros", @opts)
      assert entry.attrs["horizon"] == "medium"
    end

    test "default status is 'active'" do
      entry = BulkParser.parse_line("meta: Ler 12 livros", @opts)
      assert entry.attrs["status"] == "active"
    end

    test "default target_value is nil (not present in attrs)" do
      entry = BulkParser.parse_line("meta: Ler 12 livros", @opts)
      refute Map.has_key?(entry.attrs, "target_value")
    end
  end

  # ---------------------------------------------------------------------------
  # Req 8.6 — minimum finance line (positional format)
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — minimal finance line" do
    test "financeiro: almoço 35 returns valid finance entry" do
      entry = BulkParser.parse_line("financeiro: almoço 35", @opts)

      assert entry.status == :valid
      assert entry.type == :finance
      assert entry.attrs["amount_cents"] == 3500
    end

    test "financeiro: almoço 35 infers kind=expense via ContextInferrer" do
      entry = BulkParser.parse_line("financeiro: almoço 35", @opts)
      assert entry.attrs["kind"] == "expense"
    end

    test "financeiro: salário 5000 infers kind=income via ContextInferrer" do
      entry = BulkParser.parse_line("financeiro: salário 5000", @opts)
      assert entry.attrs["kind"] == "income"
    end

    test "financeiro applies occurred_on as today when not provided" do
      entry = BulkParser.parse_line("financeiro: almoço 35", @opts)
      assert entry.attrs["occurred_on"] == Date.to_iso8601(Date.utc_today())
    end

    test "inferred_fields includes :kind when inferred via ContextInferrer" do
      entry = BulkParser.parse_line("financeiro: almoço 35", @opts)
      assert :kind in entry.inferred_fields
    end

    test "financeiro: almoço 98,40 parses pt-BR decimal amount" do
      entry = BulkParser.parse_line("financeiro: almoço 98,40", @opts)
      assert entry.attrs["amount_cents"] == 9840
    end
  end

  # ---------------------------------------------------------------------------
  # Req 8.3 — task line with relative date in free text
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — task with relative date in free text" do
    test "tarefa: reunião amanhã resolves due_on to next day" do
      entry = BulkParser.parse_line("tarefa: reunião amanhã", @opts)

      assert entry.status == :valid
      assert entry.attrs["due_on"] == "2025-01-16"
    end

    test "tarefa: entrega sexta resolves due_on to next Friday" do
      entry = BulkParser.parse_line("tarefa: entrega sexta", @opts)
      # ref is Wednesday 2025-01-15; next Friday is 2025-01-17
      assert entry.attrs["due_on"] == "2025-01-17"
    end

    test "tarefa: revisar relatório semana que vem resolves due_on to next Monday" do
      entry = BulkParser.parse_line("tarefa: revisar relatório semana que vem", @opts)
      assert entry.attrs["due_on"] == "2025-01-20"
    end

    test "date extraction removes the date token from the title" do
      entry = BulkParser.parse_line("tarefa: reunião amanhã com equipe", @opts)
      # Title should not contain the date expression
      refute String.contains?(entry.attrs["title"], "amanhã")
    end

    test "inferred_fields includes :due_on when date was extracted from free text" do
      entry = BulkParser.parse_line("tarefa: reunião amanhã", @opts)
      assert :due_on in entry.inferred_fields
    end

    test "explicit data= takes precedence over free text date" do
      entry = BulkParser.parse_line("tarefa: reunião amanhã | data=2026-03-10", @opts)
      assert entry.attrs["due_on"] == "2026-03-10"
    end
  end

  # ---------------------------------------------------------------------------
  # Req 8.4 — task with priority indicator in free text
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — task with priority indicator in free text" do
    test "tarefa: reunião urgente maps priority to 'high'" do
      entry = BulkParser.parse_line("tarefa: reunião urgente", @opts)
      assert entry.attrs["priority"] == "high"
    end

    test "tarefa: compra baixa prioridade maps priority to 'low'" do
      entry = BulkParser.parse_line("tarefa: compra baixa prioridade", @opts)
      assert entry.attrs["priority"] == "low"
    end

    test "tarefa: entregar relatório alta prioridade maps priority to 'high'" do
      entry = BulkParser.parse_line("tarefa: entregar relatório alta prioridade", @opts)
      assert entry.attrs["priority"] == "high"
    end

    test "tarefa: tarefa baixa maps priority to 'low'" do
      entry = BulkParser.parse_line("tarefa: tarefa baixa", @opts)
      assert entry.attrs["priority"] == "low"
    end

    test "tarefa: tarefa alta maps priority to 'high'" do
      entry = BulkParser.parse_line("tarefa: tarefa alta", @opts)
      assert entry.attrs["priority"] == "high"
    end

    test "inferred_fields includes :priority when extracted from free text" do
      entry = BulkParser.parse_line("tarefa: reunião urgente", @opts)
      assert :priority in entry.inferred_fields
    end

    test "explicit prioridade= field takes precedence over free text" do
      entry = BulkParser.parse_line("tarefa: reunião urgente | prioridade=baixa", @opts)
      assert entry.attrs["priority"] == "low"
    end
  end

  # ---------------------------------------------------------------------------
  # Req 8.8 — line with only type, no body
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — line with only type (no body)" do
    test "tarefa: with empty body returns {:error, ...} entry" do
      entry = BulkParser.parse_line("tarefa:", @opts)
      assert entry.status == :invalid
      assert entry.error == "título obrigatório para tarefa"
    end

    test "tarefa: with whitespace-only body returns error" do
      entry = BulkParser.parse_line("tarefa:   ", @opts)
      assert entry.status == :invalid
      assert entry.error == "título obrigatório para tarefa"
    end

    test "meta: with empty body returns error for meta" do
      entry = BulkParser.parse_line("meta:", @opts)
      assert entry.status == :invalid
      assert entry.error == "título obrigatório para meta"
    end
  end

  # ---------------------------------------------------------------------------
  # Edge case: empty line — ignored silently
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — empty line" do
    test "empty string returns ignored entry" do
      entry = BulkParser.parse_line("", @opts)
      assert entry.status == :ignored
    end

    test "whitespace-only line returns ignored entry" do
      entry = BulkParser.parse_line("   ", @opts)
      assert entry.status == :ignored
    end

    test "ignored entry has empty attrs" do
      entry = BulkParser.parse_line("", @opts)
      assert entry.attrs == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Edge case: comment line (#) — ignored silently
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — comment line (#)" do
    test "line starting with # returns ignored entry" do
      entry = BulkParser.parse_line("# isso é um comentário", @opts)
      assert entry.status == :ignored
    end

    test "line with just # returns ignored entry" do
      entry = BulkParser.parse_line("#", @opts)
      assert entry.status == :ignored
    end

    test "comment ignored entry has empty attrs" do
      entry = BulkParser.parse_line("# comentário", @opts)
      assert entry.attrs == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Req 8.7 — equivalence: minimal line == line with explicit defaults
  # ---------------------------------------------------------------------------

  describe "parse_line/2 — equivalence with explicit defaults (Req 8.7)" do
    test "minimal task equals task with explicit default fields" do
      minimal = BulkParser.parse_line("tarefa: Comprar leite", @opts)
      explicit = BulkParser.parse_line("tarefa: Comprar leite | status=todo | prioridade=media", @opts)

      assert minimal.attrs["title"] == explicit.attrs["title"]
      assert minimal.attrs["status"] == explicit.attrs["status"]
      assert minimal.attrs["priority"] == explicit.attrs["priority"]
      assert Map.get(minimal.attrs, "due_on") == Map.get(explicit.attrs, "due_on")
    end

    test "minimal goal equals goal with explicit default fields" do
      minimal = BulkParser.parse_line("meta: Aprender Elixir", @opts)
      explicit = BulkParser.parse_line("meta: Aprender Elixir | horizonte=medio | status=ativa", @opts)

      assert minimal.attrs["title"] == explicit.attrs["title"]
      assert minimal.attrs["horizon"] == explicit.attrs["horizon"]
      assert minimal.attrs["status"] == explicit.attrs["status"]
    end
  end

  # ---------------------------------------------------------------------------
  # parse_lines/2 — batch parsing
  # ---------------------------------------------------------------------------

  describe "parse_lines/2" do
    test "parses multiple lines correctly" do
      lines = [
        "tarefa: Comprar leite",
        "meta: Aprender Elixir",
        "financeiro: almoço 35"
      ]

      entries = BulkParser.parse_lines(lines, @opts)
      assert length(entries) == 3
      assert Enum.at(entries, 0).type == :task
      assert Enum.at(entries, 1).type == :goal
      assert Enum.at(entries, 2).type == :finance
    end

    test "empty lines are included as :ignored entries" do
      lines = ["tarefa: Comprar leite", "", "meta: Aprender Elixir"]
      entries = BulkParser.parse_lines(lines, @opts)
      assert length(entries) == 3
      assert Enum.at(entries, 1).status == :ignored
    end

    test "comment lines are included as :ignored entries" do
      lines = ["# comentário", "tarefa: Comprar leite"]
      entries = BulkParser.parse_lines(lines, @opts)
      assert length(entries) == 2
      assert Enum.at(entries, 0).status == :ignored
      assert Enum.at(entries, 1).status == :valid
    end
  end

  # ---------------------------------------------------------------------------
  # Property-based tests
  # ---------------------------------------------------------------------------

  # Keywords that trigger special inference in BulkParser and would cause the
  # minimal line to differ from the explicit-defaults line.
  #
  # Date keywords: parsed by DateParser.extract_from_text/2
  # Priority keywords: parsed by extract_priority_from_text/1
  # Finance kind keywords: parsed by detect_kind_in_tokens/1 (receita/despesa)
  @trigger_keywords ~w(
    amanha amanhã hoje ontem
    segunda terca terça quarta quinta sexta sabado sábado domingo
    semana proxima próxima proximo próximo mes mês
    urgente alta baixa media média prioridade
    receita despesa income expense
    fixa fixo variavel variável recorrente mensal avulsa pontual
    credito crédito debito débito cartao cartão pix dinheiro
    aluguel supermercado alimentacao alimentação almoco almoço
    jantar cafe café transporte farmacia farmácia academia assinatura
    conta fatura uber ifood mercado salario salário freelance renda
    entrada bonus bônus dividendos reembolso
  )

  # Generator for safe alphanumeric titles (min 3 chars) that do NOT contain
  # any trigger keyword that would cause BulkParser to infer extra fields.
  defp gen_safe_title do
    StreamData.string(:alphanumeric, min_length: 3, max_length: 20)
    |> StreamData.filter(fn s ->
      s = String.downcase(s)
      # Must be non-empty after trim
      String.trim(s) != "" and
        # Must not contain any trigger keyword as a substring
        not Enum.any?(@trigger_keywords, fn kw -> String.contains?(s, kw) end) and
        # Must not look like an ISO date (YYYY-MM-DD)
        not Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, s)
    end)
  end

  # Generator for positive integer amounts (as string, no decimal) that won't
  # collide with any trigger keyword.
  defp gen_safe_amount do
    StreamData.positive_integer()
    |> StreamData.map(&Integer.to_string/1)
  end

  @tag feature: "ai-like-input-enhancements", property: 10
  property "equivalência de linha mínima com defaults explícitos" do
    # **Validates: Requirements 8.7**
    today = Date.to_iso8601(Date.utc_today())

    check all title <- gen_safe_title(),
              amount <- gen_safe_amount() do
      # ---- TASK: minimal vs explicit defaults ----
      task_minimal = BulkParser.parse_line("tarefa: #{title}", %{})
      task_explicit = BulkParser.parse_line("tarefa: #{title} | status=todo | prioridade=media", %{})

      assert task_minimal.status == :valid,
             "Expected minimal task to be :valid but got: #{inspect(task_minimal)}"

      assert task_minimal.attrs["title"] == task_explicit.attrs["title"],
             "Task title mismatch: #{inspect(task_minimal.attrs["title"])} != #{inspect(task_explicit.attrs["title"])}"

      assert task_minimal.attrs["status"] == task_explicit.attrs["status"],
             "Task status mismatch: #{inspect(task_minimal.attrs["status"])} != #{inspect(task_explicit.attrs["status"])}"

      assert task_minimal.attrs["priority"] == task_explicit.attrs["priority"],
             "Task priority mismatch: #{inspect(task_minimal.attrs["priority"])} != #{inspect(task_explicit.attrs["priority"])}"

      assert Map.get(task_minimal.attrs, "due_on") == Map.get(task_explicit.attrs, "due_on"),
             "Task due_on mismatch"

      # ---- GOAL: minimal vs explicit defaults ----
      goal_minimal = BulkParser.parse_line("meta: #{title}", %{})
      goal_explicit = BulkParser.parse_line("meta: #{title} | horizonte=medio | status=ativa", %{})

      assert goal_minimal.status == :valid,
             "Expected minimal goal to be :valid but got: #{inspect(goal_minimal)}"

      assert goal_minimal.attrs["title"] == goal_explicit.attrs["title"],
             "Goal title mismatch: #{inspect(goal_minimal.attrs["title"])} != #{inspect(goal_explicit.attrs["title"])}"

      assert goal_minimal.attrs["horizon"] == goal_explicit.attrs["horizon"],
             "Goal horizon mismatch: #{inspect(goal_minimal.attrs["horizon"])} != #{inspect(goal_explicit.attrs["horizon"])}"

      assert goal_minimal.attrs["status"] == goal_explicit.attrs["status"],
             "Goal status mismatch: #{inspect(goal_minimal.attrs["status"])} != #{inspect(goal_explicit.attrs["status"])}"

      assert Map.get(goal_minimal.attrs, "target_value") == Map.get(goal_explicit.attrs, "target_value"),
             "Goal target_value mismatch"

      # ---- FINANCE: minimal vs explicit defaults ----
      finance_minimal = BulkParser.parse_line("financeiro: #{title} #{amount}", %{})
      finance_explicit = BulkParser.parse_line("financeiro: #{title} #{amount} | occurred_on=#{today}", %{})

      assert finance_minimal.status == :valid,
             "Expected minimal finance to be :valid but got: #{inspect(finance_minimal)}"

      assert finance_minimal.attrs["occurred_on"] == finance_explicit.attrs["occurred_on"],
             "Finance occurred_on mismatch: #{inspect(finance_minimal.attrs["occurred_on"])} != #{inspect(finance_explicit.attrs["occurred_on"])}"

      assert finance_minimal.attrs["amount_cents"] == finance_explicit.attrs["amount_cents"],
             "Finance amount_cents mismatch"
    end
  end
end
