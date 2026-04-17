defmodule Organizer.Planning.AmountParserTest do
  use ExUnit.Case, async: true

  alias Organizer.Planning.AmountParser

  describe "pt-BR decimal with comma" do
    test "98,40 -> 9840" do
      assert AmountParser.parse("98,40") == {:ok, 9840}
    end

    test "1.200,50 -> 120050" do
      assert AmountParser.parse("1.200,50") == {:ok, 120050}
    end
  end

  describe "decimal with dot" do
    test "98.40 -> 9840" do
      assert AmountParser.parse("98.40") == {:ok, 9840}
    end

    test "1200.50 -> 120050" do
      assert AmountParser.parse("1200.50") == {:ok, 120050}
    end
  end

  describe "k suffix" do
    test "1k -> 100000" do
      assert AmountParser.parse("1k") == {:ok, 100_000}
    end

    test "2.5k -> 250000" do
      assert AmountParser.parse("2.5k") == {:ok, 250_000}
    end

    test "1,5k -> 150000" do
      assert AmountParser.parse("1,5k") == {:ok, 150_000}
    end

    test "uppercase K suffix also works" do
      assert AmountParser.parse("1K") == {:ok, 100_000}
    end
  end

  describe "simple integer treated as reais" do
    test "100 -> 10000" do
      assert AmountParser.parse("100") == {:ok, 10_000}
    end

    test "5000 -> 500000" do
      assert AmountParser.parse("5000") == {:ok, 500_000}
    end
  end

  describe "R$ prefix" do
    test "R$ 50,00 -> 5000" do
      assert AmountParser.parse("R$ 50,00") == {:ok, 5000}
    end

    test "R$100 -> 10000" do
      assert AmountParser.parse("R$100") == {:ok, 10_000}
    end
  end

  describe "Portuguese written-out values" do
    test "cem -> 10000" do
      assert AmountParser.parse("cem") == {:ok, 10_000}
    end

    test "cem reais -> 10000" do
      assert AmountParser.parse("cem reais") == {:ok, 10_000}
    end

    test "duzentos -> 20000" do
      assert AmountParser.parse("duzentos") == {:ok, 20_000}
    end

    test "duzentos reais -> 20000" do
      assert AmountParser.parse("duzentos reais") == {:ok, 20_000}
    end

    test "quinhentos -> 50000" do
      assert AmountParser.parse("quinhentos") == {:ok, 50_000}
    end

    test "quinhentos reais -> 50000" do
      assert AmountParser.parse("quinhentos reais") == {:ok, 50_000}
    end

    test "mil -> 100000" do
      assert AmountParser.parse("mil") == {:ok, 100_000}
    end

    test "mil reais -> 100000" do
      assert AmountParser.parse("mil reais") == {:ok, 100_000}
    end

    test "dois mil -> 200000" do
      assert AmountParser.parse("dois mil") == {:ok, 200_000}
    end
  end

  describe "edge cases" do
    test "invalid string returns {:error, :unrecognized_amount}" do
      assert AmountParser.parse("abc") == {:error, :unrecognized_amount}
    end

    test "empty string returns {:error, :unrecognized_amount}" do
      assert AmountParser.parse("") == {:error, :unrecognized_amount}
    end

    test "negative value returns {:error, :negative_amount}" do
      assert AmountParser.parse("-50") == {:error, :negative_amount}
    end

    test "negative decimal returns {:error, :negative_amount}" do
      assert AmountParser.parse("-1,50") == {:error, :negative_amount}
    end

    test "zero is valid and returns {:ok, 0}" do
      assert AmountParser.parse("0") == {:ok, 0}
    end

    test "integer passed directly is returned as-is (idempotency)" do
      assert AmountParser.parse(9840) == {:ok, 9840}
    end

    test "zero integer is also valid" do
      assert AmountParser.parse(0) == {:ok, 0}
    end

    test "negative integer returns {:error, :negative_amount}" do
      assert AmountParser.parse(-100) == {:error, :negative_amount}
    end
  end
end
