defmodule Organizer.Planning.ContextInferrerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Organizer.Planning.ContextInferrer

  describe "income terms" do
    test "salário -> :income" do
      assert ContextInferrer.infer_kind("salário") == {:ok, :income}
    end

    test "salario -> :income" do
      assert ContextInferrer.infer_kind("salario") == {:ok, :income}
    end

    test "freelance -> :income" do
      assert ContextInferrer.infer_kind("freelance") == {:ok, :income}
    end

    test "renda -> :income" do
      assert ContextInferrer.infer_kind("renda") == {:ok, :income}
    end

    test "receita -> :income" do
      assert ContextInferrer.infer_kind("receita") == {:ok, :income}
    end

    test "entrada -> :income" do
      assert ContextInferrer.infer_kind("entrada") == {:ok, :income}
    end

    test "bonus -> :income" do
      assert ContextInferrer.infer_kind("bonus") == {:ok, :income}
    end

    test "bônus -> :income" do
      assert ContextInferrer.infer_kind("bônus") == {:ok, :income}
    end

    test "dividendos -> :income" do
      assert ContextInferrer.infer_kind("dividendos") == {:ok, :income}
    end

    test "aluguel recebido -> :income" do
      assert ContextInferrer.infer_kind("aluguel recebido") == {:ok, :income}
    end

    test "reembolso -> :income" do
      assert ContextInferrer.infer_kind("reembolso") == {:ok, :income}
    end
  end

  describe "expense terms" do
    test "aluguel -> :expense" do
      assert ContextInferrer.infer_kind("aluguel") == {:ok, :expense}
    end

    test "supermercado -> :expense" do
      assert ContextInferrer.infer_kind("supermercado") == {:ok, :expense}
    end

    test "alimentacao -> :expense" do
      assert ContextInferrer.infer_kind("alimentacao") == {:ok, :expense}
    end

    test "alimentação -> :expense" do
      assert ContextInferrer.infer_kind("alimentação") == {:ok, :expense}
    end

    test "almoço -> :expense" do
      assert ContextInferrer.infer_kind("almoço") == {:ok, :expense}
    end

    test "almoco -> :expense" do
      assert ContextInferrer.infer_kind("almoco") == {:ok, :expense}
    end

    test "jantar -> :expense" do
      assert ContextInferrer.infer_kind("jantar") == {:ok, :expense}
    end

    test "cafe -> :expense" do
      assert ContextInferrer.infer_kind("cafe") == {:ok, :expense}
    end

    test "café -> :expense" do
      assert ContextInferrer.infer_kind("café") == {:ok, :expense}
    end

    test "transporte -> :expense" do
      assert ContextInferrer.infer_kind("transporte") == {:ok, :expense}
    end

    test "farmacia -> :expense" do
      assert ContextInferrer.infer_kind("farmacia") == {:ok, :expense}
    end

    test "farmácia -> :expense" do
      assert ContextInferrer.infer_kind("farmácia") == {:ok, :expense}
    end

    test "academia -> :expense" do
      assert ContextInferrer.infer_kind("academia") == {:ok, :expense}
    end

    test "assinatura -> :expense" do
      assert ContextInferrer.infer_kind("assinatura") == {:ok, :expense}
    end

    test "conta -> :expense" do
      assert ContextInferrer.infer_kind("conta") == {:ok, :expense}
    end

    test "fatura -> :expense" do
      assert ContextInferrer.infer_kind("fatura") == {:ok, :expense}
    end

    test "uber -> :expense" do
      assert ContextInferrer.infer_kind("uber") == {:ok, :expense}
    end

    test "ifood -> :expense" do
      assert ContextInferrer.infer_kind("ifood") == {:ok, :expense}
    end

    test "mercado -> :expense" do
      assert ContextInferrer.infer_kind("mercado") == {:ok, :expense}
    end
  end

  describe "capitalization variations" do
    test "SALÁRIO (uppercase) -> :income" do
      assert ContextInferrer.infer_kind("SALÁRIO") == {:ok, :income}
    end

    test "Freelance (title case) -> :income" do
      assert ContextInferrer.infer_kind("Freelance") == {:ok, :income}
    end

    test "RENDA (uppercase) -> :income" do
      assert ContextInferrer.infer_kind("RENDA") == {:ok, :income}
    end

    test "ALMOÇO (uppercase) -> :expense" do
      assert ContextInferrer.infer_kind("ALMOÇO") == {:ok, :expense}
    end

    test "Supermercado (title case) -> :expense" do
      assert ContextInferrer.infer_kind("Supermercado") == {:ok, :expense}
    end

    test "UBER (uppercase) -> :expense" do
      assert ContextInferrer.infer_kind("UBER") == {:ok, :expense}
    end

    test "Farmácia (title case with accent) -> :expense" do
      assert ContextInferrer.infer_kind("Farmácia") == {:ok, :expense}
    end
  end

  describe "terms embedded in longer text" do
    test "text containing supermercado -> :expense" do
      assert ContextInferrer.infer_kind("comprei no supermercado hoje") == {:ok, :expense}
    end

    test "text containing almoço -> :expense" do
      assert ContextInferrer.infer_kind("paguei o almoço com cartão") == {:ok, :expense}
    end

    test "text containing salário -> :income" do
      assert ContextInferrer.infer_kind("recebi meu salário hoje") == {:ok, :income}
    end

    test "text containing reembolso -> :income" do
      assert ContextInferrer.infer_kind("aguardando reembolso da empresa") == {:ok, :income}
    end
  end

  describe "unicode/accent normalization" do
    test "almoco (no accent) -> :expense" do
      assert ContextInferrer.infer_kind("almoco") == {:ok, :expense}
    end

    test "farmacia (no accent) -> :expense" do
      assert ContextInferrer.infer_kind("farmacia") == {:ok, :expense}
    end

    test "salario (no accent) -> :income" do
      assert ContextInferrer.infer_kind("salario") == {:ok, :income}
    end

    test "bonus (no accent) -> :income" do
      assert ContextInferrer.infer_kind("bonus") == {:ok, :income}
    end
  end

  describe "aluguel recebido vs aluguel conflict" do
    test "aluguel recebido -> :income (not expense)" do
      assert ContextInferrer.infer_kind("aluguel recebido") == {:ok, :income}
    end

    test "plain aluguel -> :expense" do
      assert ContextInferrer.infer_kind("aluguel") == {:ok, :expense}
    end

    test "pagamento do aluguel -> :expense" do
      assert ContextInferrer.infer_kind("pagamento do aluguel mensal") == {:ok, :expense}
    end
  end

  describe "edge cases" do
    test "empty string -> {:ok, nil}" do
      assert ContextInferrer.infer_kind("") == {:ok, nil}
    end

    test "whitespace-only string -> {:ok, nil}" do
      assert ContextInferrer.infer_kind("   ") == {:ok, nil}
    end

    test "text with no recognized terms -> {:ok, nil}" do
      assert ContextInferrer.infer_kind("reunião de equipe") == {:ok, nil}
    end

    test "unrecognized text returns {:ok, nil}" do
      assert ContextInferrer.infer_kind("xyz abc 123") == {:ok, nil}
    end

    test "conflicting terms (income + expense) -> {:ok, nil}" do
      assert ContextInferrer.infer_kind("receita do supermercado") == {:ok, nil}
    end

    test "another conflicting pair (freelance + conta) -> {:ok, nil}" do
      assert ContextInferrer.infer_kind("freelance pagar conta") == {:ok, nil}
    end

    test "nil input -> {:ok, nil}" do
      assert ContextInferrer.infer_kind(nil) == {:ok, nil}
    end
  end

  # ---------------------------------------------------------------------------
  # Property-based tests
  # ---------------------------------------------------------------------------

  # Canonical income terms as listed in the requirements (Req 4.3).
  # Both accented and unaccented forms are included since the module normalizes
  # via Unicode NFD — any capitalization variant of either form must yield :income.
  @canonical_income_terms [
    "salário",
    "salario",
    "freelance",
    "renda",
    "receita",
    "entrada",
    "bonus",
    "bônus",
    "dividendos",
    "aluguel recebido",
    "reembolso"
  ]

  # Generator: randomly uppercase or lowercase each grapheme of a string.
  defp gen_capitalization_variant(term) do
    graphemes = String.graphemes(term)

    generators = Enum.map(graphemes, fn g ->
      StreamData.boolean()
      |> StreamData.map(fn upper? ->
        if upper?, do: String.upcase(g), else: String.downcase(g)
      end)
    end)

    StreamData.fixed_list(generators)
    |> StreamData.map(&Enum.join/1)
  end

  @tag feature: "ai-like-input-enhancements", property: 9
  property "Propriedade 9: inferência de receita insensível a caixa e acentuação — Validates: Requirements 4.6" do
    check all term <- StreamData.member_of(@canonical_income_terms),
              variant <- gen_capitalization_variant(term),
              max_runs: 200 do
      assert ContextInferrer.infer_kind(variant) == {:ok, :income},
             "Expected {:ok, :income} for capitalization variant #{inspect(variant)} of term #{inspect(term)}"
    end
  end
end
