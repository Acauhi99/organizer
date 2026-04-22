defmodule Organizer.Planning.BulkParser do
  @moduledoc """
  Parses lines from the bulk capture textarea into structured entry maps.

  This module is a public facade that delegates to three focused sub-parsers:

  - `BulkParser.TaskParser`    — `tarefa:` / `task:` / `t:` lines
  - `BulkParser.FinanceParser` — `financeiro:` / `finance:` / `f:` / `receita:` / `despesa:` lines
  - `BulkParser.GoalParser`    — `meta:` / `goal:` / `g:` lines

  The public contract (`parse_line/2` and `parse_lines/2`) is unchanged.
  """

  alias Organizer.Planning.BulkParser.FinanceParser
  alias Organizer.Planning.BulkParser.GoalParser
  alias Organizer.Planning.BulkParser.TaskParser

  @doc """
  Parses a single line from the bulk textarea.

  Returns a map with keys:
    :type    - :task | :finance | :goal
    :status  - :valid | :invalid | :ignored
    :raw     - original line string
    :attrs   - map of string-keyed attributes
    :inferred_fields - list of field names that were inferred (vs explicit)
    :error   - error message string (only when status: :invalid)

  opts can include:
    :reference_date - Date.t() for relative date resolution (default: Date.utc_today())
  """
  @spec parse_line(String.t(), map()) :: map()
  def parse_line(line, opts \\ %{}) do
    reference_date = Map.get(opts, :reference_date, Date.utc_today())
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        %{raw: line, status: :ignored, attrs: %{}, inferred_fields: []}

      String.starts_with?(trimmed, "#") ->
        %{raw: line, status: :ignored, attrs: %{}, inferred_fields: []}

      String.contains?(trimmed, ":") ->
        [raw_type, raw_body] = String.split(trimmed, ":", parts: 2)
        type = normalize_token(raw_type)
        body = String.trim(raw_body)

        cond do
          type in ["tarefa", "task", "t"] ->
            TaskParser.parse(body, line, reference_date)

          type in ["financeiro", "finance", "lancamento", "lanc", "fin", "f"] ->
            FinanceParser.parse(body, nil, line, reference_date)

          type in ["meta", "goal", "g"] ->
            GoalParser.parse(body, line, reference_date)

          type in ["receita", "despesa", "income", "expense"] ->
            FinanceParser.parse(body, type, line, reference_date)

          true ->
            %{
              raw: line,
              status: :invalid,
              error: "tipo não reconhecido. Use: tarefa, financeiro ou meta",
              attrs: %{},
              inferred_fields: []
            }
        end

      true ->
        %{
          raw: line,
          status: :invalid,
          error: "formato inválido. Use o padrão tipo: conteúdo",
          attrs: %{},
          inferred_fields: []
        }
    end
  end

  @doc """
  Parses multiple lines. Empty lines and lines starting with # are :ignored.
  """
  @spec parse_lines([String.t()], map()) :: [map()]
  def parse_lines(lines, opts \\ %{}) do
    Enum.map(lines, &parse_line(&1, opts))
  end

  # ---------------------------------------------------------------------------
  # Private helpers (used only in this facade for type dispatch)
  # ---------------------------------------------------------------------------

  @spec normalize_token(String.t()) :: String.t()
  defp normalize_token(value) do
    value |> String.trim() |> String.downcase()
  end
end
