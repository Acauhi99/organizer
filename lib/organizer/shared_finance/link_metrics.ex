defmodule Organizer.SharedFinance.LinkMetrics do
  @moduledoc """
  Value struct representing monthly aggregated metrics for an AccountLink.
  Not persisted to the database.
  """

  @enforce_keys [
    :reference_month,
    :reference_year,
    :total_cents,
    :paid_a_cents,
    :paid_b_cents,
    :effective_pct_a,
    :effective_pct_b,
    :expected_pct_a,
    :expected_pct_b,
    :imbalance_detected
  ]
  defstruct [
    :reference_month,
    :reference_year,
    :total_cents,
    :paid_a_cents,
    :paid_b_cents,
    :effective_pct_a,
    :effective_pct_b,
    :expected_pct_a,
    :expected_pct_b,
    :imbalance_detected
  ]

  @type t :: %__MODULE__{
          reference_month: integer(),
          reference_year: integer(),
          total_cents: integer(),
          paid_a_cents: integer(),
          paid_b_cents: integer(),
          effective_pct_a: float(),
          effective_pct_b: float(),
          expected_pct_a: float(),
          expected_pct_b: float(),
          imbalance_detected: boolean()
        }
end
