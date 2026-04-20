defmodule Organizer.SharedFinance.LinkMetricsCalculatorPropertyTest do
  use Organizer.DataCase, async: true
  use ExUnitProperties

  alias Organizer.SharedFinance.LinkMetricsCalculator

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_shared_entry(amount_cents, amount_mine_cents) do
    entry = %Organizer.Planning.FinanceEntry{
      amount_cents: amount_cents,
      expense_profile: :variable,
      occurred_on: Date.utc_today()
    }

    %Organizer.SharedFinance.SharedEntryView{
      entry: entry,
      split_ratio_mine: 0.5,
      split_ratio_theirs: 0.5,
      amount_mine_cents: amount_mine_cents,
      amount_theirs_cents: amount_cents - amount_mine_cents
    }
  end

  defp shared_entry_generator do
    gen all(
          amount_cents <- StreamData.integer(1..1_000_000),
          amount_mine_cents <- StreamData.integer(0..amount_cents)
        ) do
      build_shared_entry(amount_cents, amount_mine_cents)
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 12: Invariante de conservação de valor nas LinkMetrics
  # Validates: Requirements 4.1, 4.7
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 12
  property "Property 12: paid_a_cents + paid_b_cents == total_cents para qualquer conjunto de SharedEntryViews" do
    check all(
            shared_entries <-
              StreamData.list_of(shared_entry_generator(), min_length: 0, max_length: 20),
            min_runs: 100
          ) do
      metrics = LinkMetricsCalculator.calculate_link_metrics(shared_entries, 0.5, 0.5)

      assert metrics.paid_a_cents + metrics.paid_b_cents == metrics.total_cents,
             "conservação de valor falhou: #{metrics.paid_a_cents} + #{metrics.paid_b_cents} != #{metrics.total_cents}"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 13: Detecção de desequilíbrio
  # Validates: Requirements 4.2
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 13
  property "Property 13: imbalance_detected é true quando |effective_pct - expected_pct| > 5.0" do
    check all(
            total_cents <- StreamData.integer(100..1_000_000),
            split_ratio_a_int <- StreamData.integer(10..90),
            delta_int <- StreamData.integer(6..30),
            min_runs: 100
          ) do
      split_ratio_a = split_ratio_a_int / 100.0
      split_ratio_b = 1.0 - split_ratio_a

      effective_pct_a = min(split_ratio_a * 100.0 + delta_int * 1.0, 100.0)
      paid_a_cents = min(round(total_cents * effective_pct_a / 100.0), total_cents)

      entry = build_shared_entry(total_cents, paid_a_cents)

      metrics =
        LinkMetricsCalculator.calculate_link_metrics([entry], split_ratio_a, split_ratio_b)

      actual_diff = abs(metrics.effective_pct_a - metrics.expected_pct_a)

      if actual_diff > 5.0 do
        assert metrics.imbalance_detected == true,
               "esperado imbalance_detected=true quando diff=#{actual_diff}"
      end
    end
  end

  @tag feature: "shared-finance", property: 13
  property "Property 13: imbalance_detected é false quando |effective_pct - expected_pct| <= 5.0" do
    check all(
            total_cents <- StreamData.integer(100..1_000_000),
            split_ratio_a_int <- StreamData.integer(10..90),
            delta_int <- StreamData.integer(0..4),
            min_runs: 100
          ) do
      split_ratio_a = split_ratio_a_int / 100.0
      split_ratio_b = 1.0 - split_ratio_a

      effective_pct_a = min(split_ratio_a * 100.0 + delta_int * 1.0, 100.0)
      paid_a_cents = min(round(total_cents * effective_pct_a / 100.0), total_cents)

      entry = build_shared_entry(total_cents, paid_a_cents)

      metrics =
        LinkMetricsCalculator.calculate_link_metrics([entry], split_ratio_a, split_ratio_b)

      actual_diff = abs(metrics.effective_pct_a - metrics.expected_pct_a)

      if actual_diff <= 5.0 do
        assert metrics.imbalance_detected == false,
               "esperado imbalance_detected=false quando diff=#{actual_diff}"
      end
    end
  end

  test "imbalance_detected é false quando total_cents é zero" do
    metrics = LinkMetricsCalculator.calculate_link_metrics([], 0.5, 0.5)

    assert metrics.total_cents == 0
    assert metrics.paid_a_cents == 0
    assert metrics.paid_b_cents == 0
    assert metrics.effective_pct_a == 0.0
    assert metrics.effective_pct_b == 0.0
    refute metrics.imbalance_detected
  end
end
