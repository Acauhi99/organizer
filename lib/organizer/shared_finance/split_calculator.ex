defmodule Organizer.SharedFinance.SplitCalculator do
  @moduledoc """
  Pure functions for calculating split ratios and reference income.
  No side effects, no GenServer.
  """

  alias Organizer.Repo
  import Ecto.Query
  alias Organizer.Planning.FinanceEntry

  @fixed_profiles [:fixed, :recurring_fixed]
  @dynamic_profiles [:variable, :recurring_variable]

  @doc """
  Calculates the reference income for a user in a given month/year.
  Includes:
  - dynamic income entries that occurred in the month
  - fixed income entries from the month, with carryover from the latest prior month
    that has fixed income (fixed/recurring_fixed)
  """
  def calculate_reference_income(user_id, month, year, repo \\ Repo) do
    {start_on, end_on} = month_bounds(month, year)
    dynamic_income = query_dynamic_income_entries_sum(user_id, start_on, end_on, repo)
    fixed_income = query_fixed_income_with_carryover(user_id, month, year, repo)

    dynamic_income + fixed_income
  end

  @doc """
  Calculates the reference income for a user in a given month/year with carryover.

  Priority:
  1. Income sum in the requested month/year (including projected fixed income)
  2. If zero, dynamic income sum from the latest previous month (<= requested month/year)
  3. If still none, 0
  """
  def calculate_reference_income_with_carryover(user_id, month, year, repo \\ Repo) do
    current_income = calculate_reference_income(user_id, month, year, repo)

    if current_income > 0 do
      current_income
    else
      query_latest_dynamic_income_month_sum_until(user_id, month, year, repo)
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

  defp query_dynamic_income_entries_sum(user_id, start_on, end_on, repo) do
    result =
      repo.one(
        from fe in FinanceEntry,
          where:
            fe.user_id == ^user_id and
              fe.kind == :income and
              fe.occurred_on >= ^start_on and
              fe.occurred_on <= ^end_on and
              (is_nil(fe.expense_profile) or fe.expense_profile in ^@dynamic_profiles),
          select: sum(fe.amount_cents)
      )

    result || 0
  end

  defp query_fixed_income_with_carryover(user_id, month, year, repo) do
    {start_on, end_on} = month_bounds(month, year)
    current_fixed_income = query_fixed_income_entries_sum(user_id, start_on, end_on, repo)

    if current_fixed_income > 0 do
      current_fixed_income
    else
      query_latest_fixed_income_month_sum_until(user_id, month, year, repo)
    end
  end

  defp query_fixed_income_entries_sum(user_id, start_on, end_on, repo) do
    result =
      repo.one(
        from fe in FinanceEntry,
          where:
            fe.user_id == ^user_id and
              fe.kind == :income and
              fe.occurred_on >= ^start_on and
              fe.occurred_on <= ^end_on and
              fe.expense_profile in ^@fixed_profiles,
          select: sum(fe.amount_cents)
      )

    result || 0
  end

  defp query_latest_fixed_income_month_sum_until(user_id, month, year, repo) do
    period_end = year |> Date.new!(month, 1) |> Date.end_of_month()

    latest_fixed_income_date =
      repo.one(
        from fe in FinanceEntry,
          where:
            fe.user_id == ^user_id and
              fe.kind == :income and
              fe.expense_profile in ^@fixed_profiles and
              fe.occurred_on <= ^period_end,
          limit: 1,
          order_by: [desc: fe.occurred_on],
          select: fe.occurred_on
      )

    case latest_fixed_income_date do
      %Date{} = date ->
        start_on = Date.beginning_of_month(date)
        end_on = Date.end_of_month(date)
        query_fixed_income_entries_sum(user_id, start_on, end_on, repo)

      _ ->
        0
    end
  end

  defp query_latest_dynamic_income_month_sum_until(user_id, month, year, repo) do
    period_end = year |> Date.new!(month, 1) |> Date.end_of_month()

    latest_income_date =
      repo.one(
        from fe in FinanceEntry,
          where:
            fe.user_id == ^user_id and
              fe.kind == :income and
              (is_nil(fe.expense_profile) or fe.expense_profile in ^@dynamic_profiles) and
              fe.occurred_on <= ^period_end,
          limit: 1,
          order_by: [desc: fe.occurred_on],
          select: fe.occurred_on
      )

    case latest_income_date do
      %Date{} = date ->
        start_on = Date.beginning_of_month(date)
        end_on = Date.end_of_month(date)
        query_dynamic_income_entries_sum(user_id, start_on, end_on, repo)

      _ ->
        0
    end
  end

  defp month_bounds(month, year) do
    start_on = Date.new!(year, month, 1)
    {start_on, Date.end_of_month(start_on)}
  end
end
