defmodule Organizer.Planning.FinanceEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Organizer.Accounts.User

  @kinds [:income, :expense]

  schema "finance_entries" do
    field :kind, Ecto.Enum, values: @kinds
    field :amount_cents, :integer
    field :category, :string
    field :description, :string
    field :occurred_on, :date

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:kind, :amount_cents, :category, :description, :occurred_on])
    |> validate_required([:kind, :amount_cents, :category, :occurred_on])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_length(:category, min: 2, max: 80)
    |> validate_length(:description, max: 300)
    |> assoc_constraint(:user)
  end
end
