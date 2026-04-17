defmodule Organizer.Planning.BulkScoring do
  @moduledoc """
  Calculates confidence scores for parsed bulk capture lines.

  Scoring is heuristic-based and considers:
  - Completeness of provided attributes
  - Number of corrections applied
  - Ambiguity in parsing (multiple possible interpretations)
  """

  @doc """
  Calculate confidence score for a parsed bulk line entry.

  Returns a map with:
  - score: 0.0-1.0 confidence
  - feedback: user-facing message about the interpretation
  - confidence_level: :high, :medium, :low for visual indication
  """
  def score_entry(%{status: :ignored}) do
    %{score: 0.0, feedback: "Linha vazia ou comentário", confidence_level: :ignored}
  end

  def score_entry(%{status: :invalid} = entry) do
    %{
      score: 0.0,
      feedback: "Erro: #{entry.error}",
      confidence_level: :error
    }
  end

  def score_entry(%{status: :valid, type: type, attrs: attrs, raw: raw} = entry) do
    # Start with base score based on how much was explicitly provided
    base_score = calculate_completeness_score(type, attrs)

    # Check if we had to correct/infer anything
    correction_penalty = calculate_correction_penalty(entry)

    # Check for ambiguity signals in the raw line
    ambiguity_penalty = calculate_ambiguity_penalty(raw, attrs)

    final_score = max(0.0, base_score - correction_penalty - ambiguity_penalty)

    confidence_level =
      cond do
        final_score >= 0.85 -> :high
        final_score >= 0.6 -> :medium
        true -> :low
      end

    feedback = generate_feedback(type, attrs, final_score)

    %{
      score: Float.round(final_score, 2),
      feedback: feedback,
      confidence_level: confidence_level
    }
  end

  @doc """
  Score multiple entries and return a summary.
  """
  def score_entries(entries) when is_list(entries) do
    scored = Enum.map(entries, &score_entry/1)

    high_count = Enum.count(scored, &(&1.confidence_level == :high))
    medium_count = Enum.count(scored, &(&1.confidence_level == :medium))
    low_count = Enum.count(scored, &(&1.confidence_level == :low))
    error_count = Enum.count(scored, &(&1.confidence_level == :error))
    ignored_count = Enum.count(scored, &(&1.confidence_level == :ignored))

    %{
      entries: scored,
      high_confidence: high_count,
      medium_confidence: medium_count,
      low_confidence: low_count,
      errors: error_count,
      ignored: ignored_count,
      average_score:
        if(Enum.count(scored, &(&1.score > 0.0)) > 0,
          do:
            Float.round(
              (scored |> Enum.map(& &1.score) |> Enum.sum()) /
                Enum.count(scored, &(&1.score > 0.0)),
              2
            ),
          else: 0.0
        )
    }
  end

  # Private helpers

  defp calculate_completeness_score(:task, attrs) do
    # Tasks need: title (required), status, priority, due_on (optional)
    base = if Map.has_key?(attrs, :title) && attrs.title != "", do: 0.6, else: 0.0

    bonus =
      Enum.count([attrs[:status], attrs[:priority], attrs[:due_on]], &(&1 not in [nil, ""]))

    # Bonus for each explicit attribute (up to 3)
    base + min(bonus * 0.1, 0.35)
  end

  defp calculate_completeness_score(:finance, attrs) do
    # Finances need: kind (required), amount (required)
    has_kind = Map.has_key?(attrs, :kind) && attrs.kind != ""
    has_amount = Map.has_key?(attrs, :amount) && attrs.amount not in [nil, ""]

    base = if has_kind and has_amount, do: 0.7, else: 0.2

    # Bonus for optional fields
    bonus =
      Enum.count(
        [attrs[:date], attrs[:category], attrs[:description], attrs[:account]],
        &(&1 not in [nil, ""])
      )

    base + min(bonus * 0.15, 0.3)
  end

  defp calculate_completeness_score(:goal, attrs) do
    # Goals need: title (required), horizon (required)
    has_title = Map.has_key?(attrs, :title) && attrs.title != ""
    has_horizon = Map.has_key?(attrs, :horizon) && attrs.horizon != ""

    base = if has_title and has_horizon, do: 0.85, else: 0.2

    # Bonus for status
    bonus = if attrs[:status] not in [nil, ""], do: 0.1, else: 0.0

    base + bonus
  end

  defp calculate_correction_penalty(%{suggested_line: nil}), do: 0.0
  defp calculate_correction_penalty(%{suggested_line: _}), do: 0.15
  defp calculate_correction_penalty(_), do: 0.0

  defp calculate_ambiguity_penalty(raw, _attrs) do
    # Check for signals of ambiguity
    penalties =
      [
        # Multiple possible separators
        (String.contains?(raw, ["|", "::", "->"]) && 0.05) || 0.0,
        # Very short line might be ambiguous
        (String.length(String.trim(raw)) < 5 && 0.05) || 0.0
      ]

    Enum.sum(penalties)
  end

  defp generate_feedback(:task, attrs, _score) do
    parts = []

    parts =
      if attrs[:title] do
        parts ++ ["Tarefa: #{String.slice(attrs.title, 0, 30)}"]
      else
        parts
      end

    parts =
      if attrs[:status] && attrs.status != "" do
        parts ++ ["status #{attrs.status}"]
      else
        parts
      end

    parts =
      if attrs[:priority] && attrs.priority != "" do
        parts ++ ["prioridade #{attrs.priority}"]
      else
        parts
      end

    Enum.join(parts, " • ")
  end

  defp generate_feedback(:finance, attrs, _score) do
    parts = []

    parts =
      if attrs[:amount] do
        parts ++ ["R$ #{attrs.amount}"]
      else
        parts
      end

    parts =
      if attrs[:kind] && attrs.kind != "" do
        parts ++ [String.upcase(to_string(attrs.kind))]
      else
        parts
      end

    parts =
      if attrs[:category] && attrs.category != "" do
        parts ++ ["categoria #{attrs.category}"]
      else
        parts
      end

    Enum.join(parts, " • ")
  end

  defp generate_feedback(:goal, attrs, _score) do
    parts = []

    parts =
      if attrs[:title] do
        parts ++ ["Meta: #{String.slice(attrs.title, 0, 30)}"]
      else
        parts
      end

    parts =
      if attrs[:horizon] && attrs.horizon != "" do
        parts ++ ["horizonte #{attrs.horizon}"]
      else
        parts
      end

    Enum.join(parts, " • ")
  end
end
