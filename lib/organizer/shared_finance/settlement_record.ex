defmodule Organizer.SharedFinance.SettlementRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "settlement_records" do
    field :amount_cents, :integer
    field :method, Ecto.Enum, values: [:pix, :ted]
    field :transferred_at, :utc_datetime
    belongs_to :settlement_cycle, Organizer.SharedFinance.SettlementCycle
    belongs_to :payer, Organizer.Accounts.User
    belongs_to :receiver, Organizer.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settlement_record, attrs) do
    settlement_record
    |> cast(attrs, [:amount_cents, :method, :transferred_at])
    |> validate_required([:amount_cents, :method, :transferred_at])
    |> validate_number(:amount_cents, greater_than: 0)
  end
end
