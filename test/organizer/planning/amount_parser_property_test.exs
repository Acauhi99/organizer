defmodule Organizer.Planning.AmountParserPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Organizer.Planning.AmountParser

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  # Generates valid monetary strings: pt-BR decimals, plain integers, k-suffixed
  defp gen_valid_monetary_string do
    StreamData.one_of([
      gen_ptbr_decimal(),
      gen_plain_integer_string(),
      gen_k_suffix_string()
    ])
  end

  # Generates strings in the format "X,YY" where X is 0..9999 and YY is 00..99
  defp gen_ptbr_decimal do
    gen all(
          x <- StreamData.integer(0..9999),
          yy <- StreamData.integer(0..99)
        ) do
      cents_str = String.pad_leading(Integer.to_string(yy), 2, "0")
      "#{x},#{cents_str}"
    end
  end

  # Generates plain integer strings like "0", "1", "100", "10000"
  defp gen_plain_integer_string do
    gen all(n <- StreamData.integer(0..10_000_000)) do
      Integer.to_string(n)
    end
  end

  # Generates k-suffixed strings like "1k", "2k", "10k"
  defp gen_k_suffix_string do
    gen all(n <- StreamData.integer(1..9999)) do
      "#{n}k"
    end
  end

  # Generates positive integers (1..10_000_000) representing cents
  defp gen_positive_cents do
    StreamData.integer(1..10_000_000)
  end

  # Replicates the private format_money/1 from dashboard_live.ex
  # cents -> "X.YY" (dot decimal, no R$ prefix)
  defp format_money(cents) when is_integer(cents) do
    value = cents / 100
    :erlang.float_to_binary(value, decimals: 2)
  end

  # ---------------------------------------------------------------------------
  # Property 6: Non-negativity of monetary values
  # Validates: Requirements 3.5, 9.5
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 6
  property "Propriedade 6: AmountParser.parse/1 nunca produz valor negativo para entradas válidas" do
    check all(
            s <- gen_valid_monetary_string(),
            min_runs: 100
          ) do
      case AmountParser.parse(s) do
        {:ok, c} ->
          assert c >= 0,
                 "parse(#{inspect(s)}) returned #{c}, which is negative"

        {:error, _} ->
          # Some generated strings may not parse (e.g., "0k" edge cases); skip
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property 7: Round-trip pt-BR
  # Validates: Requirements 3.6, 9.7
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 7
  property "Propriedade 7: round-trip monetário pt-BR — parse → format_money → parse → mesmo valor" do
    check all(
            s <- gen_ptbr_decimal(),
            min_runs: 100
          ) do
      {:ok, c} = AmountParser.parse(s)
      formatted = format_money(c)
      {:ok, c2} = AmountParser.parse(formatted)

      assert c == c2,
             "round-trip falhou: parse(#{inspect(s)})=#{c}, " <>
               "format_money(#{c})=#{inspect(formatted)}, " <>
               "parse(#{inspect(formatted)})=#{c2}"
    end
  end

  # ---------------------------------------------------------------------------
  # Property 8: Integer idempotency
  # Validates: Requirements 3.7, 9.6
  # ---------------------------------------------------------------------------

  @tag feature: "ai-like-input-enhancements", property: 8
  property "Propriedade 8: inteiro positivo passado diretamente é retornado sem modificação (idempotência)" do
    check all(
            c <- gen_positive_cents(),
            min_runs: 100
          ) do
      assert AmountParser.parse(c) == {:ok, c},
             "AmountParser.parse(#{c}) deveria retornar {:ok, #{c}}"
    end
  end
end
