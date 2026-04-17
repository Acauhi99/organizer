defmodule Organizer.Planning.ContextInferrer do
  @moduledoc """
  Infers the `kind` field (income/expense) of a financial entry from its description or category text.

  Normalization (downcase + strip accents via Unicode NFD) is applied before any comparison,
  making detection case-insensitive and accent-insensitive.
  """

  @combining_char_range 0x0300..0x036F

  # Income terms — checked via substring match after normalization.
  # "aluguel recebido" must be listed before "aluguel" so that the more
  # specific term takes precedence during income detection.
  @income_terms [
    "aluguel recebido",
    "salario",
    "freelance",
    "renda",
    "receita",
    "entrada",
    "bonus",
    "dividendos",
    "reembolso"
  ]

  # Expense-only terms — none of these overlap with the income list.
  # Note: plain "aluguel" is intentionally kept here but will only produce
  # a conflict when "aluguel recebido" was NOT already matched as income.
  @expense_terms [
    "supermercado",
    "alimentacao",
    "almoco",
    "jantar",
    "cafe",
    "transporte",
    "farmacia",
    "academia",
    "assinatura",
    "conta",
    "fatura",
    "uber",
    "ifood",
    "mercado",
    "aluguel"
  ]

  @doc """
  Infers whether the given text describes an income or expense entry.

  The text is normalized (lowercased, accents removed) before matching.

  Returns:
  - `{:ok, :income}` — only income terms found
  - `{:ok, :expense}` — only expense terms found
  - `{:ok, nil}` — no terms found, or conflicting terms (ambiguous)

  Never raises.
  """
  @spec infer_kind(String.t()) :: {:ok, :income | :expense | nil}
  def infer_kind(text) when is_binary(text) do
    normalized = normalize(text)

    income_match? = Enum.any?(@income_terms, &String.contains?(normalized, &1))

    # For expense matching we must account for the "aluguel recebido" overlap:
    # if "aluguel recebido" was matched as income we should not also count plain
    # "aluguel" as an expense hit for the same segment.  The simplest approach:
    # remove all matched income substrings from the normalized text before
    # checking expense terms.
    normalized_for_expense =
      if income_match? do
        Enum.reduce(@income_terms, normalized, fn term, acc ->
          if String.contains?(acc, term), do: String.replace(acc, term, ""), else: acc
        end)
      else
        normalized
      end

    expense_match? = Enum.any?(@expense_terms, &String.contains?(normalized_for_expense, &1))

    result =
      cond do
        income_match? and expense_match? -> nil
        income_match? -> :income
        expense_match? -> :expense
        true -> nil
      end

    {:ok, result}
  end

  def infer_kind(_text), do: {:ok, nil}

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
end
