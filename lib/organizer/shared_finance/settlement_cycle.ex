defmodule Organizer.SharedFinance.SettlementCycle do
  use Ecto.Schema
  import Ecto.Changeset

  schema "settlement_cycles" do
    field :reference_month, :integer
    field :reference_year, :integer
    field :status, Ecto.Enum, values: [:open, :settled]
    field :balance_cents, :integer, default: 0
    field :confirmed_by_a, :boolean, default: false
    field :confirmed_by_b, :boolean, default: false
    field :settled_at, :utc_datetime
    belongs_to :account_link, Organizer.SharedFinance.AccountLink
    belongs_to :debtor, Organizer.Accounts.User
    has_many :settlement_records, Organizer.SharedFinance.SettlementRecord

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settlement_cycle, attrs) do
    settlement_cycle
    |> cast(attrs, [
      :reference_month,
      :reference_year,
      :status,
      :balance_cents,
      :debtor_id,
      :confirmed_by_a,
      :confirmed_by_b,
      :settled_at
    ])
    |> validate_required([:reference_month, :reference_year, :status])
    |> unique_constraint([:account_link_id, :reference_month, :reference_year],
      name: :settlement_cycles_link_month_index
    )
  end
end
