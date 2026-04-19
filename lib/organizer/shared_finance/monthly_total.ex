defmodule Organizer.SharedFinance.MonthlyTotal do
  @moduledoc """
  Value struct representing the total shared amount for a given month/year.
  Not persisted to the database.
  """

  @enforce_keys [:month, :year, :total_cents]
  defstruct [:month, :year, :total_cents]

  @type t :: %__MODULE__{
          month: integer(),
          year: integer(),
          total_cents: integer()
        }
end
