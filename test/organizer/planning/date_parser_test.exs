defmodule Organizer.Planning.DateParserTest do
  use ExUnit.Case, async: true

  alias Organizer.Planning.DateParser

  # Reference date: 2025-01-15, a Wednesday (day_of_week == 3)
  @ref ~D[2025-01-15]

  # ---------------------------------------------------------------------------
  # resolve/2 — fixed expressions
  # ---------------------------------------------------------------------------

  describe "resolve/2 — relative expressions" do
    test "hoje returns the reference date" do
      assert DateParser.resolve("hoje", @ref) == {:ok, @ref}
    end

    test "amanha returns reference + 1" do
      assert DateParser.resolve("amanha", @ref) == {:ok, ~D[2025-01-16]}
    end

    test "amanhã (accented) returns reference + 1" do
      assert DateParser.resolve("amanhã", @ref) == {:ok, ~D[2025-01-16]}
    end

    test "depois de amanha returns reference + 2" do
      assert DateParser.resolve("depois de amanha", @ref) == {:ok, ~D[2025-01-17]}
    end

    test "depois de amanhã (accented) returns reference + 2" do
      assert DateParser.resolve("depois de amanhã", @ref) == {:ok, ~D[2025-01-17]}
    end

    test "semana que vem returns next Monday" do
      # ref is Wednesday 2025-01-15; next Monday is 2025-01-20
      assert DateParser.resolve("semana que vem", @ref) == {:ok, ~D[2025-01-20]}
    end

    test "proxima semana returns next Monday" do
      assert DateParser.resolve("proxima semana", @ref) == {:ok, ~D[2025-01-20]}
    end

    test "próxima semana (accented) returns next Monday" do
      assert DateParser.resolve("próxima semana", @ref) == {:ok, ~D[2025-01-20]}
    end

    test "proximo mes returns first day of next month" do
      assert DateParser.resolve("proximo mes", @ref) == {:ok, ~D[2025-02-01]}
    end

    test "próximo mês (accented) returns first day of next month" do
      assert DateParser.resolve("próximo mês", @ref) == {:ok, ~D[2025-02-01]}
    end

    test "proximo mes at end of year rolls over to next year" do
      assert DateParser.resolve("proximo mes", ~D[2025-12-10]) == {:ok, ~D[2026-01-01]}
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/2 — weekday expressions
  # Ref: Wednesday 2025-01-15
  # Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6, Sun=7
  # ---------------------------------------------------------------------------

  describe "resolve/2 — weekdays (never same day as reference)" do
    test "segunda returns next Monday (2025-01-20)" do
      assert DateParser.resolve("segunda", @ref) == {:ok, ~D[2025-01-20]}
    end

    test "terca returns next Tuesday (2025-01-21)" do
      assert DateParser.resolve("terca", @ref) == {:ok, ~D[2025-01-21]}
    end

    test "terça (accented) returns next Tuesday" do
      assert DateParser.resolve("terça", @ref) == {:ok, ~D[2025-01-21]}
    end

    test "quarta returns next Wednesday (2025-01-22) — never today" do
      # ref IS a Wednesday; must return NEXT Wednesday, not today
      assert DateParser.resolve("quarta", @ref) == {:ok, ~D[2025-01-22]}
    end

    test "quinta returns next Thursday (2025-01-16)" do
      assert DateParser.resolve("quinta", @ref) == {:ok, ~D[2025-01-16]}
    end

    test "sexta returns next Friday (2025-01-17)" do
      assert DateParser.resolve("sexta", @ref) == {:ok, ~D[2025-01-17]}
    end

    test "sabado returns next Saturday (2025-01-18)" do
      assert DateParser.resolve("sabado", @ref) == {:ok, ~D[2025-01-18]}
    end

    test "sábado (accented) returns next Saturday" do
      assert DateParser.resolve("sábado", @ref) == {:ok, ~D[2025-01-18]}
    end

    test "domingo returns next Sunday (2025-01-19)" do
      assert DateParser.resolve("domingo", @ref) == {:ok, ~D[2025-01-19]}
    end
  end

  describe "resolve/2 — proxima <dia> expressions" do
    test "proxima segunda" do
      assert DateParser.resolve("proxima segunda", @ref) == {:ok, ~D[2025-01-20]}
    end

    test "próxima terça (accented)" do
      assert DateParser.resolve("próxima terça", @ref) == {:ok, ~D[2025-01-21]}
    end

    test "proxima sexta" do
      assert DateParser.resolve("proxima sexta", @ref) == {:ok, ~D[2025-01-17]}
    end

    test "proxima domingo" do
      assert DateParser.resolve("proxima domingo", @ref) == {:ok, ~D[2025-01-19]}
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/2 — ISO 8601 idempotency
  # ---------------------------------------------------------------------------

  describe "resolve/2 — ISO 8601 idempotency" do
    test "a valid ISO date string is returned unchanged" do
      assert DateParser.resolve("2026-04-20", @ref) == {:ok, ~D[2026-04-20]}
    end

    test "ISO date in the past is returned unchanged (no mutation)" do
      assert DateParser.resolve("2020-03-01", @ref) == {:ok, ~D[2020-03-01]}
    end

    test "ISO date same as reference is returned unchanged" do
      assert DateParser.resolve("2025-01-15", @ref) == {:ok, ~D[2025-01-15]}
    end

    test "ISO date with surrounding whitespace is handled" do
      assert DateParser.resolve("  2026-06-01  ", @ref) == {:ok, ~D[2026-06-01]}
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/2 — error cases
  # ---------------------------------------------------------------------------

  describe "resolve/2 — unrecognized expressions" do
    test "unrecognized string returns error" do
      assert DateParser.resolve("foobar", @ref) == {:error, :unrecognized_expression}
    end

    test "empty string returns error" do
      assert DateParser.resolve("", @ref) == {:error, :unrecognized_expression}
    end

    test "partial weekday does not match" do
      assert DateParser.resolve("seg", @ref) == {:error, :unrecognized_expression}
    end

    test "invalid ISO string returns error" do
      assert DateParser.resolve("2025-13-01", @ref) == {:error, :unrecognized_expression}
    end

    test "proxima with unrecognized weekday returns error" do
      assert DateParser.resolve("proxima xyz", @ref) == {:error, :unrecognized_expression}
    end
  end

  # ---------------------------------------------------------------------------
  # extract_from_text/2
  # ---------------------------------------------------------------------------

  describe "extract_from_text/2" do
    test "extracts 'amanhã' from free text and returns remaining text" do
      {date, remaining} = DateParser.extract_from_text("reunião amanhã com equipe", @ref)
      assert date == ~D[2025-01-16]
      assert remaining == "reunião com equipe"
    end

    test "extracts 'hoje' from free text" do
      {date, remaining} = DateParser.extract_from_text("entrega hoje cedo", @ref)
      assert date == ~D[2025-01-15]
      assert remaining == "entrega cedo"
    end

    test "extracts day-of-week from free text" do
      {date, remaining} = DateParser.extract_from_text("reunião sexta com o cliente", @ref)
      assert date == ~D[2025-01-17]
      assert remaining == "reunião com o cliente"
    end

    test "extracts 'depois de amanhã' (multi-word) before single-word matches" do
      {date, remaining} = DateParser.extract_from_text("entrega depois de amanhã", @ref)
      assert date == ~D[2025-01-17]
      assert remaining == "entrega"
    end

    test "returns {nil, original} when no date expression is found" do
      {date, remaining} = DateParser.extract_from_text("comprar leite e ovos", @ref)
      assert date == nil
      assert remaining == "comprar leite e ovos"
    end

    test "returns {nil, original} for empty string" do
      {date, remaining} = DateParser.extract_from_text("", @ref)
      assert date == nil
      assert remaining == ""
    end

    test "remaining text is trimmed" do
      {_date, remaining} = DateParser.extract_from_text("amanhã", @ref)
      assert remaining == ""
    end

    test "extracts 'proxima semana' from free text" do
      {date, remaining} = DateParser.extract_from_text("revisar relatório proxima semana", @ref)
      assert date == ~D[2025-01-20]
      assert remaining == "revisar relatório"
    end
  end
end
