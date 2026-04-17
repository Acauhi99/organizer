defmodule Organizer.Planning.AmountParser do
  @moduledoc """
  Converts textual monetary representations to integer cents.

  Supports pt-BR comma decimals, dot thousand separators, `k` suffix,
  `R$` prefix, plain integers (as reais), and a basic subset of
  Portuguese words.
  """

  @type parse_result ::
          {:ok, non_neg_integer()} | {:error, :unrecognized_amount | :negative_amount}

  @portuguese_words %{
    "cem" => 10_000,
    "duzentos" => 20_000,
    "quinhentos" => 50_000,
    "mil" => 100_000,
    "dois mil" => 200_000
  }

  @doc """
  Parses a monetary value string (or integer) to integer cents.

  Returns `{:ok, cents}` where `cents >= 0`, `{:error, :unrecognized_amount}`,
  or `{:error, :negative_amount}`.

  Never raises.
  """
  @spec parse(String.t() | non_neg_integer()) :: parse_result()
  def parse(value) when is_integer(value) do
    if value < 0, do: {:error, :negative_amount}, else: {:ok, value}
  end

  def parse(value) when is_binary(value) do
    try do
      do_parse(value)
    rescue
      _ -> {:error, :unrecognized_amount}
    end
  end

  # --- private ---

  defp do_parse(""), do: {:error, :unrecognized_amount}

  defp do_parse(value) do
    # Strip R$ prefix and surrounding whitespace
    stripped = value |> String.trim() |> strip_currency_prefix()

    cond do
      # k suffix
      String.ends_with?(stripped, "k") or String.ends_with?(stripped, "K") ->
        parse_k_suffix(stripped)

      # Numeric string (possibly pt-BR or dot decimal)
      numeric_string?(stripped) ->
        parse_numeric(stripped)

      # Portuguese words
      true ->
        parse_portuguese(stripped)
    end
  end

  defp strip_currency_prefix(value) do
    value
    |> String.replace(~r/^R\$\s*/u, "")
    |> String.trim()
  end

  defp numeric_string?(value) do
    Regex.match?(~r/^-?[\d.,]+$/u, value)
  end

  defp parse_k_suffix(value) do
    base = value |> String.slice(0..-2//1) |> String.trim()

    normalized = normalize_amount_numeric_string(base)

    case Float.parse(normalized) do
      {float_val, ""} ->
        cents = round(float_val * 100_000)
        check_non_negative(cents)

      _ ->
        {:error, :unrecognized_amount}
    end
  end

  defp parse_numeric(value) do
    normalized = normalize_amount_numeric_string(value)

    case Float.parse(normalized) do
      {float_val, ""} ->
        cents = round(float_val * 100)
        check_non_negative(cents)

      _ ->
        {:error, :unrecognized_amount}
    end
  end

  defp parse_portuguese(value) do
    normalized = value |> String.downcase() |> String.trim()

    # Strip optional "reais" suffix
    without_reais =
      normalized
      |> String.replace(~r/\s+reais$/u, "")
      |> String.trim()

    case Map.get(@portuguese_words, without_reais) do
      nil -> {:error, :unrecognized_amount}
      cents -> {:ok, cents}
    end
  end

  defp check_non_negative(cents) when cents < 0, do: {:error, :negative_amount}
  defp check_non_negative(cents), do: {:ok, cents}

  # Ported from dashboard_live.ex normalize_amount_numeric_string/1
  defp normalize_amount_numeric_string(value) do
    has_comma = String.contains?(value, ",")
    has_dot = String.contains?(value, ".")

    cond do
      has_comma and has_dot ->
        if last_index(value, ",") > last_index(value, ".") do
          value |> String.replace(".", "") |> String.replace(",", ".")
        else
          String.replace(value, ",", "")
        end

      has_comma ->
        if Regex.match?(~r/,\d{1,2}$/u, value) do
          String.replace(value, ",", ".")
        else
          String.replace(value, ",", "")
        end

      has_dot ->
        if Regex.match?(~r/\.\d{1,2}$/u, value) do
          value
        else
          String.replace(value, ".", "")
        end

      true ->
        value
    end
  end

  defp last_index(string, char) do
    string
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.filter(fn {c, _} -> c == char end)
    |> List.last()
    |> elem(1)
  end
end
