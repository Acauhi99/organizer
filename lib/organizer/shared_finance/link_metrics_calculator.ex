defmodule Organizer.SharedFinance.LinkMetricsCalculator do
  @moduledoc """
  Pure functions for calculating link metrics and recurring variable trends.
  No side effects.
  """

  alias Organizer.SharedFinance.{LinkMetrics, MonthlyTotal}

  @imbalance_threshold 5.0

  @doc """
  Calculates LinkMetrics for a given set of SharedEntryViews and split ratios.
  """
  def calculate_link_metrics(shared_entries, split_ratio_a, split_ratio_b, opts \\ []) do
    total_cents = Enum.sum(Enum.map(shared_entries, & &1.entry.amount_cents))
    paid_a_cents = Enum.sum(Enum.map(shared_entries, & &1.amount_mine_cents))
    paid_b_cents = total_cents - paid_a_cents

    {effective_pct_a, effective_pct_b} =
      if total_cents == 0 do
        {0.0, 0.0}
      else
        effective_a = paid_a_cents / total_cents * 100.0
        {effective_a, 100.0 - effective_a}
      end

    expected_pct_a = split_ratio_a * 100.0
    expected_pct_b = split_ratio_b * 100.0

    imbalance_detected =
      total_cents > 0 and abs(effective_pct_a - expected_pct_a) > @imbalance_threshold

    reference_date = Keyword.get(opts, :reference_date, Date.utc_today())

    %LinkMetrics{
      reference_month: reference_date.month,
      reference_year: reference_date.year,
      total_cents: total_cents,
      paid_a_cents: paid_a_cents,
      paid_b_cents: paid_b_cents,
      effective_pct_a: effective_pct_a,
      effective_pct_b: effective_pct_b,
      expected_pct_a: expected_pct_a,
      expected_pct_b: expected_pct_b,
      imbalance_detected: imbalance_detected
    }
  end

  @doc """
  Calculates the monthly trend of recurring_variable shared entries for the last N months.
  Returns a list of %MonthlyTotal{} sorted by (year, month) ascending.
  """
  def calculate_recurring_variable_trend(shared_entries, months \\ 6) do
    today = Date.utc_today()
    cutoff = Date.add(today, -months * 30)

    shared_entries
    |> Enum.filter(fn se ->
      se.entry.expense_profile == :recurring_variable and
        Date.compare(se.entry.occurred_on, cutoff) != :lt
    end)
    |> Enum.group_by(fn se ->
      {se.entry.occurred_on.year, se.entry.occurred_on.month}
    end)
    |> Enum.map(fn {{year, month}, entries} ->
      total = Enum.sum(Enum.map(entries, & &1.entry.amount_cents))
      %MonthlyTotal{year: year, month: month, total_cents: total}
    end)
    |> Enum.sort_by(fn mt -> {mt.year, mt.month} end)
  end
end
