defmodule Organizer.SharedFinance.MonthlyDebtSummary do
  @moduledoc """
  Consolidated debt status for a collaboration month.
  """

  @enforce_keys [
    :reference_month,
    :reference_year,
    :original_amount_cents,
    :outstanding_amount_cents,
    :status,
    :confirmed_by_a,
    :confirmed_by_b,
    :settled
  ]
  defstruct [
    :reference_month,
    :reference_year,
    :original_amount_cents,
    :outstanding_amount_cents,
    :status,
    :confirmed_by_a,
    :confirmed_by_b,
    :settled
  ]

  @type status :: :open | :partial | :settled

  @type t :: %__MODULE__{
          reference_month: integer(),
          reference_year: integer(),
          original_amount_cents: integer(),
          outstanding_amount_cents: integer(),
          status: status(),
          confirmed_by_a: boolean(),
          confirmed_by_b: boolean(),
          settled: boolean()
        }
end
