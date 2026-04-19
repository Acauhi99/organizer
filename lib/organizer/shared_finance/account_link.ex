defmodule Organizer.SharedFinance.AccountLink do
  use Ecto.Schema
  import Ecto.Changeset

  schema "account_links" do
    field :status, Ecto.Enum, values: [:active, :inactive]
    belongs_to :user_a, Organizer.Accounts.User
    belongs_to :user_b, Organizer.Accounts.User
    belongs_to :invite, Organizer.SharedFinance.Invite
    has_many :settlement_cycles, Organizer.SharedFinance.SettlementCycle

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(account_link, attrs) do
    account_link
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end
end
