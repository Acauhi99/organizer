defmodule Organizer.SharedFinance.SplitCalculator do
  @moduledoc """
  Pure functions for calculating split ratios and reference income.
  No side effects, no GenServer.
  """

  alias Organizer.Repo
  import Ecto.Query

  @doc """
  Calculates the reference income for a user in a given month/year.
  = sum of FinanceEntry amounts where kind=:income and occurred_on is in month/year.
  """
  def calculate_reference_income(user_id, month, year, repo \\ Repo) do
    income_entry_sum = query_income_entries_sum(user_id, month, year, repo)
    income_entry_sum
  end

  @doc """
  Calculates the reference income for a user in a given month/year with carryover.

  Priority:
  1. Income sum in the requested month/year
  2. If zero, income sum from the latest previous month (<= requested month/year)
  3. If still none, 0
  """
  def calculate_reference_income_with_carryover(user_id, month, year, repo \\ Repo) do
    current_income = calculate_reference_income(user_id, month, year, repo)

    if current_income > 0 do
      current_income
    else
      query_latest_income_month_sum_until(user_id, month, year, repo)
    end
  end

  @doc """
  Calculates the split ratio between two users based on their reference incomes.
  Returns {ratio_a, ratio_b} where ratio_a + ratio_b == 1.0.
  When income_a + income_b == 0, returns {1.0, 0.0}.
  """
  def calculate_split_ratio(income_a, income_b) do
    total = income_a + income_b

    if total == 0 do
      {1.0, 0.0}
    else
      ratio_a = income_a / total
      ratio_b = income_b / total
      {ratio_a, ratio_b}
    end
  end

  @doc """
  Splits an amount in cents according to ratio_a.
  Returns {amount_a, amount_b} where amount_a + amount_b == amount_cents.
  amount_a = round(amount_cents * ratio_a), amount_b = amount_cents - amount_a
  """
  def split_amount(amount_cents, ratio_a) do
    amount_a = round(amount_cents * ratio_a)
    amount_b = amount_cents - amount_a
    {amount_a, amount_b}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp query_income_entries_sum(user_id, month, year, repo) do
    result =
      repo.one(
        from fe in Organizer.Planning.FinanceEntry,
          where:
            fe.user_id == ^user_id and
              fe.kind == :income and
              fragment("strftime('%m', ?)", fe.occurred_on) == ^zero_pad(month) and
              fragment("strftime('%Y', ?)", fe.occurred_on) == ^to_string(year),
          select: sum(fe.amount_cents)
      )

    result || 0
  end

  defp query_latest_income_month_sum_until(user_id, month, year, repo) do
    period_end = year |> Date.new!(month, 1) |> Date.end_of_month()

    result =
      repo.one(
        from fe in Organizer.Planning.FinanceEntry,
          where:
            fe.user_id == ^user_id and
              fe.kind == :income and
              fe.occurred_on <= ^period_end,
          group_by: [
            fragment("strftime('%Y', ?)", fe.occurred_on),
            fragment("strftime('%m', ?)", fe.occurred_on)
          ],
          order_by: [
            desc: fragment("strftime('%Y', ?)", fe.occurred_on),
            desc: fragment("strftime('%m', ?)", fe.occurred_on)
          ],
          limit: 1,
          select: sum(fe.amount_cents)
      )

    result || 0
  end

  defp zero_pad(month) when month < 10, do: "0#{month}"
  defp zero_pad(month), do: to_string(month)
end
