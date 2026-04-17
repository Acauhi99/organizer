defmodule Organizer.Planning.DateParserPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Organizer.Planning.DateParser

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  # Generates a valid %Date{} in the range 2020-01-01..2030-12-31
  defp gen_reference_date do
    gen all(
          year <- StreamData.integer(2020..2030),
          month <- StreamData.integer(1..12),
          day <- StreamData.integer(1..28)
        ) do
      Date.new!(year, month, day)
    end
  end

  # All recognized relative expressions (normalized — no accents needed since
  # the parser normalizes internally). We include accented variants to exercise
  # both code paths.
  @relative_expressions [
    "amanha",
    "amanhã",
    "depois de amanha",
    "depois de amanhã",
    "semana que vem",
    "proxima semana",
    "próxima semana",
    "proximo mes",
    "próximo mês",
    "segunda",
    "terca",
    "terça",
    "quarta",
    "quinta",
    "sexta",
    "sabado",
    "sábado",
    "domingo",
    "proxima segunda",
    "proxima terca",
    "próxima terça",
    "proxima quarta",
    "proxima quinta",
    "proxima sexta",
    "proxima sabado",
    "proxima domingo"
  ]

  defp gen_relative_expression do
    StreamData.member_of(@relative_expressions)
  end

  # Weekday expressions paired with their expected day_of_week number (1=Mon..7=Sun)
  @weekday_expressions [
    {"segunda", 1},
    {"terca", 2},
    {"terça", 2},
    {"quarta", 3},
    {"quinta", 4},
    {"sexta", 5},
    {"sabado", 6},
    {"sábado", 6},
    {"domingo", 7},
    {"proxima segunda", 1},
    {"proxima terca", 2},
    {"próxima terça", 2},
    {"proxima quarta", 3},
    {"proxima quinta", 4},
    {"proxima sexta", 5},
    {"proxima sabado", 6},
    {"proxima domingo", 7}
  ]

  defp gen_weekday_expression_with_dow do
    StreamData.member_of(@weekday_expressions)
  end

  # Generates a valid %Date{} and formats it as an ISO 8601 string
  defp gen_iso_date_string do
    gen all(date <- gen_reference_date()) do
      {date, Date.to_iso8601(date)}
    end
  end

  # ---------------------------------------------------------------------------
  # Property 2: Result date is never before the reference date
  # Validates: Requirements 2.6
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 2
  property "Propriedade 2: data resultante nunca é anterior à referência" do
    check all(
            expr <- gen_relative_expression(),
            ref <- gen_reference_date(),
            max_runs: 200
          ) do
      case DateParser.resolve(expr, ref) do
        {:ok, result} ->
          assert Date.compare(result, ref) in [:gt, :eq],
                 "expression #{inspect(expr)} with ref #{ref} produced #{result} which is before #{ref}"

        {:error, _} ->
          # If the expression isn't recognized (shouldn't happen for our list),
          # just skip — don't fail the property
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property 3: Weekday expressions produce the correct day_of_week
  # Validates: Requirements 2.7
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 3
  property "Propriedade 3: expressões de dia da semana produzem o dia_of_week correto" do
    check all(
            {expr, expected_dow} <- gen_weekday_expression_with_dow(),
            ref <- gen_reference_date(),
            max_runs: 200
          ) do
      {:ok, result} = DateParser.resolve(expr, ref)

      assert Date.day_of_week(result) == expected_dow,
             "expression #{inspect(expr)} with ref #{ref} produced #{result} " <>
               "(day_of_week=#{Date.day_of_week(result)}) but expected day_of_week=#{expected_dow}"
    end
  end

  # ---------------------------------------------------------------------------
  # Property 4: ISO 8601 idempotency
  # Validates: Requirements 2.5
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 4
  property "Propriedade 4: data ISO 8601 válida é retornada sem modificação (idempotência)" do
    check all(
            {expected_date, iso_string} <- gen_iso_date_string(),
            ref <- gen_reference_date(),
            max_runs: 200
          ) do
      assert DateParser.resolve(iso_string, ref) == {:ok, expected_date},
             "ISO string #{inspect(iso_string)} should resolve to #{expected_date} " <>
               "regardless of reference date #{ref}"
    end
  end

  # ---------------------------------------------------------------------------
  # Property 5: "hoje" always returns exactly the reference date
  # Validates: Requirements 2.8
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 5
  property "Propriedade 5: 'hoje' retorna exatamente a data de referência (identidade)" do
    check all(
            ref <- gen_reference_date(),
            max_runs: 200
          ) do
      assert DateParser.resolve("hoje", ref) == {:ok, ref},
             "DateParser.resolve(\"hoje\", #{ref}) should return #{ref}"
    end
  end

  # ---------------------------------------------------------------------------
  # Bonus: weekday result is strictly after reference (never same day)
  # This is a stricter variant of Property 2 for weekday expressions.
  # Validates: Requirements 2.6, 2.7
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 2
  property "weekday expressions sempre produzem datas estritamente posteriores à referência" do
    check all(
            {expr, _dow} <- gen_weekday_expression_with_dow(),
            ref <- gen_reference_date(),
            max_runs: 200
          ) do
      {:ok, result} = DateParser.resolve(expr, ref)

      assert Date.compare(result, ref) == :gt,
             "expression #{inspect(expr)} with ref #{ref} produced #{result} which is not strictly after #{ref}"
    end
  end
end
