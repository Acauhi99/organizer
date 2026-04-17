defmodule Organizer.Planning.BulkScoringTest do
  use ExUnit.Case, async: true

  alias Organizer.Planning.BulkScoring

  describe "score_entry/1" do
    test "returns ignored for ignored entries" do
      entry = %{status: :ignored}
      result = BulkScoring.score_entry(entry)

      assert result.confidence_level == :ignored
      assert result.score == 0.0
    end

    test "returns error for invalid entries" do
      entry = %{status: :invalid, error: "Invalid format"}
      result = BulkScoring.score_entry(entry)

      assert result.confidence_level == :error
      assert result.score == 0.0
      assert String.contains?(result.feedback, "Erro")
    end

    test "scores high confidence for complete task" do
      entry = %{
        status: :valid,
        type: :task,
        raw: "Buy milk - priority high - status todo",
        attrs: %{
          title: "Buy milk",
          status: "todo",
          priority: "high",
          due_on: "2024-04-20"
        }
      }

      result = BulkScoring.score_entry(entry)

      assert result.confidence_level == :high
      assert result.score >= 0.8
      assert String.contains?(result.feedback, "Tarefa")
    end

    test "scores medium confidence for partial entry" do
      entry = %{
        status: :valid,
        type: :task,
        raw: "Buy milk",
        attrs: %{title: "Buy milk"}
      }

      result = BulkScoring.score_entry(entry)

      assert result.confidence_level == :medium
      assert 0.6 <= result.score and result.score < 0.85
    end

    test "scores finance entries correctly" do
      entry = %{
        status: :valid,
        type: :finance,
        raw: "R$ 100 - food",
        attrs: %{amount: "100", kind: "expense", category: "food"}
      }

      result = BulkScoring.score_entry(entry)

      assert result.confidence_level == :high
      assert String.contains?(result.feedback, "100")
    end

    test "scores goal entries correctly" do
      entry = %{
        status: :valid,
        type: :goal,
        raw: "Learn Elixir - week",
        attrs: %{title: "Learn Elixir", horizon: "week"}
      }

      result = BulkScoring.score_entry(entry)

      assert result.confidence_level == :high
      assert String.contains?(result.feedback, "Meta")
    end
  end

  describe "score_entries/1" do
    test "returns summary statistics" do
      entries = [
        %{status: :valid, type: :task, raw: "Task 1", attrs: %{title: "Task 1"}},
        %{status: :valid, type: :task, raw: "Task 2", attrs: %{title: "Task 2"}},
        %{status: :invalid, error: "Bad format"},
        %{status: :ignored}
      ]

      result = BulkScoring.score_entries(entries)

      assert is_list(result.entries)
      assert result.high_confidence >= 0
      assert result.medium_confidence >= 0
      assert result.errors == 1
      assert result.ignored == 1
      assert is_float(result.average_score)
    end
  end
end
