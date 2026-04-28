defmodule Organizer.SharedFinance.SharedEntryDebt do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:open, :partial, :settled]

  @derive {
    Flop.Schema,
    filterable: [:status, :reference_month, :reference_year, :outstanding_amount_cents],
    sortable: [:reference_year, :reference_month, :outstanding_amount_cents, :inserted_at],
    default_order: %{
      order_by: [:reference_year, :reference_month, :inserted_at],
      order_directions: [:desc, :desc, :desc]
    },
    default_limit: 20,
    max_limit: 100
  }

  schema "shared_entry_debts" do
    field :reference_month, :integer
    field :reference_year, :integer
    field :original_amount_cents, :integer
    field :outstanding_amount_cents, :integer
    field :status, Ecto.Enum, values: @statuses

    belongs_to :account_link, Organizer.SharedFinance.AccountLink
    belongs_to :finance_entry, Organizer.Planning.FinanceEntry
    belongs_to :debtor, Organizer.Accounts.User
    belongs_to :creditor, Organizer.Accounts.User

    has_many :settlement_record_allocations, Organizer.SharedFinance.SettlementRecordAllocation

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(shared_entry_debt, attrs) do
    shared_entry_debt
    |> cast(attrs, [
      :account_link_id,
      :finance_entry_id,
      :debtor_id,
      :creditor_id,
      :reference_month,
      :reference_year,
      :original_amount_cents,
      :outstanding_amount_cents,
      :status
    ])
    |> validate_required([
      :account_link_id,
      :finance_entry_id,
      :debtor_id,
      :creditor_id,
      :reference_month,
      :reference_year,
      :original_amount_cents,
      :outstanding_amount_cents,
      :status
    ])
    |> validate_number(:reference_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:reference_year,
      greater_than_or_equal_to: 2000,
      less_than_or_equal_to: 9999
    )
    |> validate_number(:original_amount_cents, greater_than: 0)
    |> validate_number(:outstanding_amount_cents, greater_than_or_equal_to: 0)
    |> validate_outstanding_bounds()
    |> unique_constraint(:finance_entry_id)
  end

  defp validate_outstanding_bounds(changeset) do
    original = get_field(changeset, :original_amount_cents)
    outstanding = get_field(changeset, :outstanding_amount_cents)

    if is_integer(original) and is_integer(outstanding) and outstanding > original do
      add_error(
        changeset,
        :outstanding_amount_cents,
        "must be less than or equal to original_amount_cents"
      )
    else
      changeset
    end
  end
end
