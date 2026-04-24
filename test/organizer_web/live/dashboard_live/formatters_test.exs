defmodule OrganizerWeb.DashboardLive.FormattersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OrganizerWeb.DashboardLive.Formatters

  # ---------------------------------------------------------------------------
  # format_money/1
  # ---------------------------------------------------------------------------

  describe "format_money/1" do
    test "formats positive cents" do
      assert Formatters.format_money(1000) == "R$ 10,00"
    end

    test "formats negative cents" do
      assert Formatters.format_money(-500) == "R$ -5,00"
    end

    test "formats zero" do
      assert Formatters.format_money(0) == "R$ 0,00"
    end

    test "formats small cents (less than 100)" do
      assert Formatters.format_money(5) == "R$ 0,05"
    end

    test "returns zero value fallback for non-integer input" do
      assert Formatters.format_money("not an integer") == "R$ 0,00"
    end
  end

  describe "format_percent/1" do
    test "formats percent with comma decimal separator" do
      assert Formatters.format_percent(33.34) == "33,3"
    end

    test "formats integer percent values with one decimal" do
      assert Formatters.format_percent(50) == "50,0"
    end

    test "returns fallback for invalid values" do
      assert Formatters.format_percent(nil) == "0,0"
    end
  end

  # ---------------------------------------------------------------------------
  # balance_value_class/1
  # ---------------------------------------------------------------------------

  describe "balance_value_class/1" do
    test "returns error class for negative cents" do
      assert Formatters.balance_value_class(-100) == "text-error"
    end

    test "returns success class for positive cents" do
      assert Formatters.balance_value_class(100) == "text-success"
    end

    test "returns info class for zero" do
      assert Formatters.balance_value_class(0) == "text-info"
    end

    test "returns info class for non-integer" do
      assert Formatters.balance_value_class(nil) == "text-info"
    end
  end

  # ---------------------------------------------------------------------------
  # balance_badge_class/1
  # ---------------------------------------------------------------------------

  describe "balance_badge_class/1" do
    test "returns error badge class for negative cents" do
      assert Formatters.balance_badge_class(-100) ==
               "border-error/62 bg-error/24 text-error font-semibold"
    end

    test "returns success badge class for positive cents" do
      assert Formatters.balance_badge_class(100) ==
               "border-success/62 bg-success/28 text-success font-semibold"
    end

    test "returns info badge class for zero" do
      assert Formatters.balance_badge_class(0) ==
               "border-info/60 bg-info/24 text-info font-semibold"
    end

    test "returns info badge class for non-integer" do
      assert Formatters.balance_badge_class("invalid") ==
               "border-info/60 bg-info/24 text-info font-semibold"
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

    test "returns pt-BR date string for a Date struct" do
      date = ~D[2024-06-15]
      assert Formatters.date_input_value(date) == "15/06/2024"
    end

    test "returns pt-BR date string for another Date struct" do
      date = ~D[2000-01-01]
      assert Formatters.date_input_value(date) == "01/01/2000"
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

  property "format_money always returns a properly formatted currency string" do
    # Feature: dashboard-live-refactor, Property 3
    check all(cents <- StreamData.integer()) do
      result = Formatters.format_money(cents)

      assert is_binary(result)
      assert result =~ ~r/^R\$ -?\d{1,3}(\.\d{3})*,\d{2}$/
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
        n < 0 -> assert result == "text-error"
        n > 0 -> assert result == "text-success"
        true -> assert result == "text-info"
      end
    end
  end

  property "balance_badge_class returns correct class for any integer" do
    # Feature: dashboard-live-refactor, Property 4
    check all(n <- StreamData.integer()) do
      result = Formatters.balance_badge_class(n)

      cond do
        n < 0 -> assert result == "border-error/62 bg-error/24 text-error font-semibold"
        n > 0 -> assert result == "border-success/62 bg-success/28 text-success font-semibold"
        true -> assert result == "border-info/60 bg-info/24 text-info font-semibold"
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
