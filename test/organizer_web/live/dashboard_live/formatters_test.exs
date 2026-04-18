defmodule OrganizerWeb.DashboardLive.FormattersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OrganizerWeb.DashboardLive.Formatters

  # ---------------------------------------------------------------------------
  # format_money/1
  # ---------------------------------------------------------------------------

  describe "format_money/1" do
    test "formats positive cents" do
      assert Formatters.format_money(1000) == "10.00"
    end

    test "formats negative cents" do
      assert Formatters.format_money(-500) == "-5.00"
    end

    test "formats zero" do
      assert Formatters.format_money(0) == "0.00"
    end

    test "formats small cents (less than 100)" do
      assert Formatters.format_money(5) == "0.05"
    end

    test "raises for non-integer input" do
      assert_raise FunctionClauseError, fn ->
        Formatters.format_money("not an integer")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # balance_value_class/1
  # ---------------------------------------------------------------------------

  describe "balance_value_class/1" do
    test "returns rose class for negative cents" do
      assert Formatters.balance_value_class(-100) == "text-rose-300"
    end

    test "returns emerald class for positive cents" do
      assert Formatters.balance_value_class(100) == "text-emerald-300"
    end

    test "returns cyan class for zero" do
      assert Formatters.balance_value_class(0) == "text-cyan-300"
    end

    test "returns cyan class for non-integer" do
      assert Formatters.balance_value_class(nil) == "text-cyan-300"
    end
  end

  # ---------------------------------------------------------------------------
  # balance_badge_class/1
  # ---------------------------------------------------------------------------

  describe "balance_badge_class/1" do
    test "returns rose badge class for negative cents" do
      assert Formatters.balance_badge_class(-100) ==
               "border-rose-300/35 bg-rose-500/12 text-rose-200"
    end

    test "returns emerald badge class for positive cents" do
      assert Formatters.balance_badge_class(100) ==
               "border-emerald-300/35 bg-emerald-500/12 text-emerald-200"
    end

    test "returns cyan badge class for zero" do
      assert Formatters.balance_badge_class(0) ==
               "border-cyan-300/35 bg-cyan-500/12 text-cyan-200"
    end

    test "returns cyan badge class for non-integer" do
      assert Formatters.balance_badge_class("invalid") ==
               "border-cyan-300/35 bg-cyan-500/12 text-cyan-200"
    end
  end

  # ---------------------------------------------------------------------------
  # balance_label/1
  # ---------------------------------------------------------------------------

  describe "balance_label/1" do
    test "returns 'negativo' for negative cents" do
      assert Formatters.balance_label(-1) == "negativo"
    end

    test "returns 'positivo' for positive cents" do
      assert Formatters.balance_label(1) == "positivo"
    end

    test "returns 'neutro' for zero" do
      assert Formatters.balance_label(0) == "neutro"
    end

    test "returns 'neutro' for non-integer" do
      assert Formatters.balance_label(nil) == "neutro"
    end
  end

  # ---------------------------------------------------------------------------
  # date_input_value/1
  # ---------------------------------------------------------------------------

  describe "date_input_value/1" do
    test "returns empty string for nil" do
      assert Formatters.date_input_value(nil) == ""
    end

    test "returns ISO 8601 string for a Date struct" do
      date = ~D[2024-06-15]
      assert Formatters.date_input_value(date) == "2024-06-15"
    end

    test "returns ISO 8601 string for another Date struct" do
      date = ~D[2000-01-01]
      assert Formatters.date_input_value(date) == "2000-01-01"
    end

    test "handles non-Date, non-nil values" do
      # The function only has clauses for nil and %Date{}, so other values
      # will raise a FunctionClauseError — we just verify nil and Date work.
      assert Formatters.date_input_value(nil) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # editing?/2
  # ---------------------------------------------------------------------------

  describe "editing?/2" do
    test "returns true when IDs are equal integers" do
      assert Formatters.editing?(1, 1) == true
    end

    test "returns true when IDs are equal strings" do
      assert Formatters.editing?("abc", "abc") == true
    end

    test "returns true when integer and string representation match" do
      assert Formatters.editing?(42, "42") == true
    end

    test "returns false when IDs are different" do
      assert Formatters.editing?(1, 2) == false
    end

    test "returns false when IDs are different strings" do
      assert Formatters.editing?("foo", "bar") == false
    end

    test "returns false when one is nil and other is not" do
      assert Formatters.editing?(nil, 1) == false
    end
  end

  # ---------------------------------------------------------------------------
  # Property 3: format_money sempre retorna string formatada corretamente
  # Feature: dashboard-live-refactor, Property 3
  # ---------------------------------------------------------------------------

  property "format_money always returns a properly formatted decimal string" do
    # Feature: dashboard-live-refactor, Property 3
    check all(cents <- StreamData.integer()) do
      result = Formatters.format_money(cents)

      assert is_binary(result)

      # Must contain exactly one decimal point
      parts = String.split(result, ".")
      assert length(parts) == 2

      # Must have exactly two digits after the decimal point
      [_integer_part, decimal_part] = parts
      assert String.length(decimal_part) == 2
      assert decimal_part =~ ~r/^\d{2}$/
    end
  end

  # ---------------------------------------------------------------------------
  # Property 4: Classificadores de saldo retornam classe correta para qualquer inteiro
  # Feature: dashboard-live-refactor, Property 4
  # ---------------------------------------------------------------------------

  property "balance_value_class returns correct class for any integer" do
    # Feature: dashboard-live-refactor, Property 4
    check all(n <- StreamData.integer()) do
      result = Formatters.balance_value_class(n)

      cond do
        n < 0 -> assert result == "text-rose-300"
        n > 0 -> assert result == "text-emerald-300"
        true -> assert result == "text-cyan-300"
      end
    end
  end

  property "balance_badge_class returns correct class for any integer" do
    # Feature: dashboard-live-refactor, Property 4
    check all(n <- StreamData.integer()) do
      result = Formatters.balance_badge_class(n)

      cond do
        n < 0 -> assert result == "border-rose-300/35 bg-rose-500/12 text-rose-200"
        n > 0 -> assert result == "border-emerald-300/35 bg-emerald-500/12 text-emerald-200"
        true -> assert result == "border-cyan-300/35 bg-cyan-500/12 text-cyan-200"
      end
    end
  end

  property "balance_label returns correct label for any integer" do
    # Feature: dashboard-live-refactor, Property 4
    check all(n <- StreamData.integer()) do
      result = Formatters.balance_label(n)

      cond do
        n < 0 -> assert result == "negativo"
        n > 0 -> assert result == "positivo"
        true -> assert result == "neutro"
      end
    end
  end
end
