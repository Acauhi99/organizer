defmodule OrganizerWeb.DashboardLive.Formatters do
  @moduledoc """
  Pure formatting and UI helper functions for the DashboardLive template.

  This module is imported in `OrganizerWeb.DashboardLive` so that the HEEx
  template can call all functions without a module prefix.
  """

  @spec format_money(integer() | any()) :: String.t()
  def format_money(cents) when is_integer(cents) do
    value = cents / 100
    :erlang.float_to_binary(value, decimals: 2)
  end

  @spec format_percent(number() | any()) :: float()
  def format_percent(value) when is_number(value), do: Float.round(value * 1.0, 1)
  def format_percent(_value), do: 0.0

  @spec date_input_value(Date.t() | nil | any()) :: String.t()
  def date_input_value(nil), do: ""
  def date_input_value(%Date{} = date), do: Date.to_iso8601(date)

  @spec editing?(any(), any()) :: boolean()
  def editing?(editing_id, id) do
    to_string(editing_id) == to_string(id)
  end

  @spec balance_value_class(integer() | any()) :: String.t()
  def balance_value_class(cents) when is_integer(cents) and cents < 0, do: "text-rose-300"
  def balance_value_class(cents) when is_integer(cents) and cents > 0, do: "text-emerald-300"
  def balance_value_class(_cents), do: "text-cyan-300"

  @spec balance_badge_class(integer() | any()) :: String.t()
  def balance_badge_class(cents) when is_integer(cents) and cents < 0,
    do: "border-rose-300/35 bg-rose-500/12 text-rose-200"

  def balance_badge_class(cents) when is_integer(cents) and cents > 0,
    do: "border-emerald-300/35 bg-emerald-500/12 text-emerald-200"

  def balance_badge_class(_cents), do: "border-cyan-300/35 bg-cyan-500/12 text-cyan-200"

  @spec balance_label(integer() | any()) :: String.t()
  def balance_label(cents) when is_integer(cents) and cents < 0, do: "negativo"
  def balance_label(cents) when is_integer(cents) and cents > 0, do: "positivo"
  def balance_label(_cents), do: "neutro"

  @spec capacity_gap_class(integer() | any()) :: String.t()
  def capacity_gap_class(gap) when is_integer(gap) and gap > 0, do: "text-rose-300"
  def capacity_gap_class(gap) when is_integer(gap) and gap < 0, do: "text-emerald-300"
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
  def risk_badge_class(:high), do: "border border-rose-300/30 bg-rose-500/15 text-rose-100"
  def risk_badge_class(:medium), do: "border border-amber-300/30 bg-amber-500/15 text-amber-100"
  def risk_badge_class(_), do: "border border-emerald-300/30 bg-emerald-500/15 text-emerald-100"

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
end
