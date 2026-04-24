defmodule OrganizerWeb.DashboardLive.Formatters do
  @moduledoc """
  Pure formatting and UI helper functions for the DashboardLive template.

  This module is imported in `OrganizerWeb.DashboardLive` so that the HEEx
  template can call all functions without a module prefix.
  """

  alias Organizer.DateSupport

  @spec format_money(integer() | any()) :: String.t()
  def format_money(cents) when is_integer(cents) do
    abs_cents = abs(cents)
    integer_part = abs_cents |> div(100) |> Integer.to_string() |> add_thousands_separator()
    decimal_part = abs_cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign = if cents < 0, do: "-", else: ""

    "R$ #{sign}#{integer_part},#{decimal_part}"
  end

  def format_money(_), do: "R$ 0,00"

  @spec format_percent(number() | any()) :: String.t()
  def format_percent(value) when is_number(value), do: format_decimal_ptbr(value * 1.0, 1)
  def format_percent(_value), do: "0,0"

  @spec date_input_value(Date.t() | nil | any()) :: String.t()
  def date_input_value(nil), do: ""
  def date_input_value(%Date{} = date), do: DateSupport.format_pt_br(date)

  @spec editing?(any(), any()) :: boolean()
  def editing?(editing_id, id) do
    to_string(editing_id) == to_string(id)
  end

  @spec balance_value_class(integer() | any()) :: String.t()
  def balance_value_class(cents) when is_integer(cents) and cents < 0, do: "text-error"
  def balance_value_class(cents) when is_integer(cents) and cents > 0, do: "text-success"
  def balance_value_class(_cents), do: "text-info"

  @spec balance_badge_class(integer() | any()) :: String.t()
  def balance_badge_class(cents) when is_integer(cents) and cents < 0,
    do: "border-error/40 bg-error/12 text-error-content"

  def balance_badge_class(cents) when is_integer(cents) and cents > 0,
    do: "border-success/40 bg-success/12 text-success-content"

  def balance_badge_class(_cents), do: "border-info/40 bg-info/12 text-info-content"

  @spec balance_label(integer() | any()) :: String.t()
  def balance_label(cents) when is_integer(cents) and cents < 0, do: "negativo"
  def balance_label(cents) when is_integer(cents) and cents > 0, do: "positivo"
  def balance_label(_cents), do: "neutro"

  @spec capacity_gap_class(integer() | any()) :: String.t()
  def capacity_gap_class(gap) when is_integer(gap) and gap > 0, do: "text-error"
  def capacity_gap_class(gap) when is_integer(gap) and gap < 0, do: "text-success"
  def capacity_gap_class(_gap), do: "text-base-content"

  @spec capacity_gap_label(integer() | any()) :: String.t()
  def capacity_gap_label(gap) when is_integer(gap) and gap > 0,
    do: "Acima da capacidade em #{gap}"

  def capacity_gap_label(gap) when is_integer(gap) and gap < 0,
    do: "Folga de #{abs(gap)}"

  def capacity_gap_label(_gap), do: "Capacidade equilibrada"

  @spec burnout_level_label(atom() | any()) :: String.t()
  def burnout_level_label(:high), do: "Alto"
  def burnout_level_label(:medium), do: "Médio"
  def burnout_level_label(_), do: "Baixo"

  @spec risk_badge_class(atom() | any()) :: String.t()
  def risk_badge_class(:high), do: "border border-error/58 bg-error/24 text-error-content"

  def risk_badge_class(:medium),
    do: "border border-warning/58 bg-warning/28 text-warning-content"

  def risk_badge_class(_), do: "border border-success/58 bg-success/26 text-success-content"

  @spec finance_entry_meta_line(map()) :: String.t()
  def finance_entry_meta_line(entry) do
    [
      finance_kind_label(Map.get(entry, :kind)),
      finance_expense_profile_label(Map.get(entry, :expense_profile)),
      finance_payment_method_label(Map.get(entry, :payment_method)),
      format_money(Map.get(entry, :amount_cents)),
      entry |> Map.get(:occurred_on) |> date_input_value()
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" • ")
  end

  @spec completion_rate(integer(), integer()) :: float()
  def completion_rate(completed, total)
      when is_integer(completed) and is_integer(total) and total > 0 do
    Float.round(completed * 100 / total, 1)
  end

  def completion_rate(_completed, _total), do: 0.0

  @spec metric_bar_width(number() | any()) :: float()
  def metric_bar_width(value) when is_number(value) do
    value
    |> max(0.0)
    |> min(100.0)
    |> Float.round(1)
  end

  def metric_bar_width(_value), do: 0.0

  defp finance_kind_label(:income), do: "receita"
  defp finance_kind_label(:expense), do: "despesa"
  defp finance_kind_label(value) when is_atom(value), do: Atom.to_string(value)
  defp finance_kind_label(_), do: "tipo pendente"

  defp finance_expense_profile_label(:fixed), do: "fixa"
  defp finance_expense_profile_label(:variable), do: "variável"
  defp finance_expense_profile_label(nil), do: nil
  defp finance_expense_profile_label(value) when is_atom(value), do: Atom.to_string(value)
  defp finance_expense_profile_label(_), do: nil

  defp finance_payment_method_label(:credit), do: "crédito"
  defp finance_payment_method_label(:debit), do: "débito"
  defp finance_payment_method_label(nil), do: nil
  defp finance_payment_method_label(value) when is_atom(value), do: Atom.to_string(value)
  defp finance_payment_method_label(_), do: nil

  defp format_decimal_ptbr(value, decimals) when is_number(value) and decimals >= 0 do
    rounded_value = Float.round(value * 1.0, decimals)
    sign = if rounded_value < 0, do: "-", else: ""

    normalized =
      rounded_value
      |> abs()
      |> :erlang.float_to_binary(decimals: decimals)

    case String.split(normalized, ".") do
      [integer_part, decimal_part] ->
        formatted_integer = add_thousands_separator(integer_part)
        sign <> formatted_integer <> "," <> decimal_part

      [integer_part] ->
        sign <> add_thousands_separator(integer_part)
    end
  end

  defp add_thousands_separator(value) when is_binary(value) do
    value
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(".")
    |> String.reverse()
  end
end
