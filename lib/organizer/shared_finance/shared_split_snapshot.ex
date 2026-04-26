defmodule Organizer.SharedFinance.SharedSplitSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "shared_split_snapshots" do
    field :account_link_id, :integer
    field :finance_entry_id, :integer
    field :reference_month, :integer
    field :reference_year, :integer
    field :split_mode, Ecto.Enum, values: [:income_ratio, :manual, :owner_fallback]
    field :ratio_a, :float
    field :ratio_b, :float
    field :amount_a_cents, :integer
    field :amount_b_cents, :integer
    field :income_a_cents, :integer
    field :income_b_cents, :integer
    field :calculated_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :account_link_id,
      :finance_entry_id,
      :reference_month,
      :reference_year,
      :split_mode,
      :ratio_a,
      :ratio_b,
      :amount_a_cents,
      :amount_b_cents,
      :income_a_cents,
      :income_b_cents,
      :calculated_at
    ])
    |> validate_required([
      :account_link_id,
      :finance_entry_id,
      :reference_month,
      :reference_year,
      :split_mode,
      :ratio_a,
      :ratio_b,
      :amount_a_cents,
      :amount_b_cents,
      :income_a_cents,
      :income_b_cents,
      :calculated_at
    ])
    |> validate_number(:reference_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:reference_year,
      greater_than_or_equal_to: 2000,
      less_than_or_equal_to: 9999
    )
    |> validate_number(:amount_a_cents, greater_than_or_equal_to: 0)
    |> validate_number(:amount_b_cents, greater_than_or_equal_to: 0)
    |> validate_number(:income_a_cents, greater_than_or_equal_to: 0)
    |> validate_number(:income_b_cents, greater_than_or_equal_to: 0)
    |> validate_number(:ratio_a, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:ratio_b, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
