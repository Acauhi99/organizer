defmodule Organizer.SharedFinance.AccountLink do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:status, :inserted_at],
    sortable: [:inserted_at, :updated_at, :id],
    default_order: %{order_by: [:inserted_at], order_directions: [:desc]},
    default_limit: 20,
    max_limit: 10_000
  }

  schema "account_links" do
    field :status, Ecto.Enum, values: [:active, :inactive]
    belongs_to :user_a, Organizer.Accounts.User
    belongs_to :user_b, Organizer.Accounts.User
    belongs_to :invite, Organizer.SharedFinance.Invite
    has_many :settlement_cycles, Organizer.SharedFinance.SettlementCycle
    has_many :shared_entry_debts, Organizer.SharedFinance.SharedEntryDebt

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(account_link, attrs) do
    account_link
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end
end
