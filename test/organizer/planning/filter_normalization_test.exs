defmodule Organizer.Planning.FilterNormalizationTest do
  use ExUnit.Case, async: true

  alias Organizer.Planning.FilterNormalization

  describe "normalize_filter_value/3" do
    test "returns ok with nil for nil input" do
      assert {:ok, nil} =
               FilterNormalization.normalize_filter_value(nil, [:low, :medium, :high], :priority)
    end

    test "returns ok with nil for empty string" do
      assert {:ok, nil} =
               FilterNormalization.normalize_filter_value("", [:low, :medium, :high], :priority)
    end

    test "returns ok with nil for 'all'" do
      assert {:ok, nil} =
               FilterNormalization.normalize_filter_value(
                 "all",
                 [:low, :medium, :high],
                 :priority
               )
    end

    test "matches exact value" do
      assert {:ok, :low} =
               FilterNormalization.normalize_filter_value(
                 "low",
                 [:low, :medium, :high],
                 :priority
               )
    end

    test "matches atom value when valid" do
      assert {:ok, :low} =
               FilterNormalization.normalize_filter_value(:low, [:low, :medium, :high], :priority)
    end

    test "returns error for invalid atom value" do
      assert {:error, {:validation, %{priority: ["is invalid"]}}} =
               FilterNormalization.normalize_filter_value(
                 :invalid,
                 [:low, :medium, :high],
                 :priority
               )
    end

    test "matches case-insensitive" do
      assert {:ok, :low} =
               FilterNormalization.normalize_filter_value(
                 "LOW",
                 [:low, :medium, :high],
                 :priority
               )

      assert {:ok, :medium} =
               FilterNormalization.normalize_filter_value(
                 "MeDiUm",
                 [:low, :medium, :high],
                 :priority
               )
    end

    test "matches Portuguese priority aliases" do
      allowed = [:low, :medium, :high]

      assert {:ok, :low} = FilterNormalization.normalize_filter_value("baixa", allowed, :priority)

      assert {:ok, :medium} =
               FilterNormalization.normalize_filter_value("média", allowed, :priority)

      assert {:ok, :medium} =
               FilterNormalization.normalize_filter_value("media", allowed, :priority)

      assert {:ok, :high} = FilterNormalization.normalize_filter_value("alta", allowed, :priority)

      assert {:ok, :high} =
               FilterNormalization.normalize_filter_value("urgente", allowed, :priority)
    end

    test "matches Portuguese status aliases" do
      allowed = [:todo, :in_progress, :done]

      assert {:ok, :todo} = FilterNormalization.normalize_filter_value("fazer", allowed, :status)

      assert {:ok, :todo} =
               FilterNormalization.normalize_filter_value("pendente", allowed, :status)

      assert {:ok, :in_progress} =
               FilterNormalization.normalize_filter_value("em_andamento", allowed, :status)

      assert {:ok, :in_progress} =
               FilterNormalization.normalize_filter_value("em andamento", allowed, :status)

      assert {:ok, :done} =
               FilterNormalization.normalize_filter_value("concluído", allowed, :status)

      assert {:ok, :done} = FilterNormalization.normalize_filter_value("pronto", allowed, :status)
    end

    test "handles fuzzy matching for typos" do
      allowed = [:low, :medium, :high]

      # Similar strings should match (typo tolerance)
      assert {:ok, :low} = FilterNormalization.normalize_filter_value("lw", allowed, :priority)
      assert {:ok, :high} = FilterNormalization.normalize_filter_value("hgh", allowed, :priority)
    end

    test "returns error for completely invalid input" do
      assert {:error, {:validation, %{priority: ["is invalid"]}}} =
               FilterNormalization.normalize_filter_value(
                 "xyz",
                 [:low, :medium, :high],
                 :priority
               )
    end
  end

  describe "calculate_similarity/2" do
    test "returns 1.0 for identical strings" do
      assert FilterNormalization.calculate_similarity("low", "low") == 1.0
    end

    test "returns 0.0 for completely different strings" do
      # Strings with no common characters should have very low similarity
      similarity = FilterNormalization.calculate_similarity("a", "b")
      assert similarity < 0.5
    end

    test "returns similarity score between 0 and 1" do
      similarity = FilterNormalization.calculate_similarity("low", "lw")
      assert 0.0 <= similarity and similarity <= 1.0
      assert similarity > 0.5
    end
  end
end
