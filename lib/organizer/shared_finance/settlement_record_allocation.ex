defmodule Organizer.SharedFinance.SettlementRecordAllocation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "settlement_record_allocations" do
    field :amount_cents, :integer

    belongs_to :settlement_record, Organizer.SharedFinance.SettlementRecord
    belongs_to :shared_entry_debt, Organizer.SharedFinance.SharedEntryDebt

    timestamps(type: :utc_datetime)
  end

  def changeset(allocation, attrs) do
    allocation
    |> cast(attrs, [:settlement_record_id, :shared_entry_debt_id, :amount_cents])
    |> validate_required([:settlement_record_id, :shared_entry_debt_id, :amount_cents])
    |> validate_number(:amount_cents, greater_than: 0)
  end
end
