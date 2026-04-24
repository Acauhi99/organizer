defmodule Organizer.Planning.FilterNormalization do
  @moduledoc """
  Normalizes and validates filter values with typo tolerance.

  Supports:
  - Exact matching (fast path)
  - Case-insensitive matching
  - Common variations and aliases (e.g. "baixa" -> "low" for priority)
  - Fuzzy matching for partial input
  """

  @doc """
  Normalize a filter value to a valid enum, with typo tolerance.

  Returns {:ok, atom} if found, {:error, reason} otherwise.
  """
  def normalize_filter_value(value, _allowed_atoms, _field) when is_nil(value),
    do: {:ok, nil}

  def normalize_filter_value("", _allowed_atoms, _field), do: {:ok, nil}

  def normalize_filter_value("all", _allowed_atoms, _field), do: {:ok, nil}

  def normalize_filter_value(value, allowed_atoms, field) when is_atom(value) do
    if value in allowed_atoms do
      {:ok, value}
    else
      {:error, {:validation, %{field => ["is invalid"]}}}
    end
  end

  def normalize_filter_value(value, allowed_atoms, field) when is_binary(value) do
    # Try exact match first
    normalized = String.downcase(value)

    # Step 1: Exact match
    exact = Enum.find(allowed_atoms, &(Atom.to_string(&1) == value))

    if is_atom(exact) and exact != nil do
      {:ok, exact}
    else
      # Step 2: Case-insensitive match
      case_result =
        Enum.find(allowed_atoms, fn atom ->
          String.downcase(Atom.to_string(atom)) == normalized
        end)

      if is_atom(case_result) and case_result != nil do
        {:ok, case_result}
      else
        # Step 3: Language aliases
        aliases = %{
          "fazer" => :todo,
          "baixa" => :low,
          "media" => :medium,
          "média" => :medium,
          "alta" => :high,
          "urgente" => :high
        }

        alias_result = Map.get(aliases, normalized)

        if is_atom(alias_result) and alias_result != nil and alias_result in allowed_atoms do
          {:ok, alias_result}
        else
          # Step 4: Extended language aliases (status, finance, etc.)
          extended_result = find_language_alias(normalized, allowed_atoms)

          if is_atom(extended_result) and extended_result != nil do
            {:ok, extended_result}
          else
            # Step 5: Fuzzy matching for typos
            fuzzy_result = find_fuzzy_match(normalized, allowed_atoms)

            if is_atom(fuzzy_result) and fuzzy_result != nil do
              {:ok, fuzzy_result}
            else
              {:error, {:validation, %{field => ["is invalid"]}}}
            end
          end
        end
      end
    end
  end

  def normalize_filter_value(_value, _allowed_atoms, field),
    do: {:error, {:validation, %{field => ["is invalid"]}}}

  @doc """
  Debug helper to test case-insensitive matching
  """
  def debug_case_insensitive(value, allowed_atoms) do
    find_case_insensitive(value, allowed_atoms)
  end

  @doc """
  Debug helper to test fuzzy matching
  """
  def debug_fuzzy(value, allowed_atoms) do
    find_fuzzy_match(value, allowed_atoms)
  end

  # Private helpers

  defp find_case_insensitive(value, allowed_atoms) do
    normalized_value = String.downcase(value)

    Enum.find(allowed_atoms, fn atom ->
      String.downcase(Atom.to_string(atom)) == normalized_value
    end)
  end

  defp find_language_alias(value, allowed_atoms) do
    normalized = String.downcase(String.trim(value))

    # Map common Portuguese variations to English enums
    aliases = %{
      # Task status aliases
      "fazer" => "todo",
      "pendente" => "todo",
      "em_andamento" => "in_progress",
      "em andamento" => "in_progress",
      "progresso" => "in_progress",
      "concluído" => "done",
      "pronto" => "done",
      "finalizado" => "done",
      # Priority aliases
      "baixa" => "low",
      "média" => "medium",
      "media" => "medium",
      "alta" => "high",
      "urgente" => "high",
      # Finance kind aliases
      "receita" => "income",
      "entrada" => "income",
      "despesa" => "expense",
      "saída" => "expense",
      "transfer" => "transfer",
      "transf" => "transfer"
    }

    case Map.get(aliases, normalized) do
      nil -> nil
      alias_value -> find_exact_atom(alias_value, allowed_atoms)
    end
  end

  defp find_exact_atom(value, allowed_atoms) when is_binary(value) do
    Enum.find(allowed_atoms, &(Atom.to_string(&1) == value))
  end

  defp find_fuzzy_match(value, allowed_atoms) do
    normalized_value = String.downcase(String.trim(value))

    # Only match if the user input is at least 2 characters
    if String.length(normalized_value) < 2 do
      nil
    else
      # Find best match based on string similarity
      atom_strings = Enum.map(allowed_atoms, fn atom -> {atom, Atom.to_string(atom)} end)

      atom_strings
      |> Enum.map(fn {atom, str} ->
        similarity = calculate_similarity(normalized_value, String.downcase(str))
        {atom, similarity}
      end)
      |> Enum.sort_by(fn {_atom, similarity} -> similarity end, :desc)
      |> case do
        [{best_atom, similarity} | _] when similarity > 0.65 ->
          best_atom

        _ ->
          nil
      end
    end
  end

  @doc """
  Calculate Levenshtein distance-based similarity between two strings.
  Returns a value between 0.0 and 1.0.
  """
  def calculate_similarity(str1, str2) do
    distance = levenshtein_distance(String.graphemes(str1), String.graphemes(str2))
    max_len = max(String.length(str1), String.length(str2))

    if max_len == 0 do
      1.0
    else
      1.0 - distance / max_len
    end
  end

  defp levenshtein_distance(s1, s2) do
    case {s1, s2} do
      {[], s2} ->
        length(s2)

      {s1, []} ->
        length(s1)

      {[h | t1], [h | t2]} ->
        levenshtein_distance(t1, t2)

      {s1 = [_ | t1], s2 = [_ | t2]} ->
        1 +
          min(
            levenshtein_distance(t1, t2),
            min(levenshtein_distance(s1, t2), levenshtein_distance(t1, s2))
          )
    end
  end
end
