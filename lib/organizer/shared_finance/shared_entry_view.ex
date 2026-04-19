defmodule Organizer.SharedFinance.SharedEntryView do
  @moduledoc """
  Value struct representing a shared finance entry with split ratio and calculated amounts.
  Not persisted to the database.
  """

  @enforce_keys [
    :entry,
    :split_ratio_mine,
    :split_ratio_theirs,
    :amount_mine_cents,
    :amount_theirs_cents
  ]
  defstruct [
    :entry,
    :split_ratio_mine,
    :split_ratio_theirs,
    :amount_mine_cents,
    :amount_theirs_cents
  ]

  @type t :: %__MODULE__{
          entry: Organizer.Planning.FinanceEntry.t(),
          split_ratio_mine: float(),
          split_ratio_theirs: float(),
          amount_mine_cents: integer(),
          amount_theirs_cents: integer()
        }
end
