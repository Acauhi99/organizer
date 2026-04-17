defmodule Organizer.Planning.FinanceEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Organizer.Accounts.User

  @kinds [:income, :expense]
  @expense_profiles [:fixed, :variable]
  @payment_methods [:credit, :debit]

  schema "finance_entries" do
    field :kind, Ecto.Enum, values: @kinds
    field :expense_profile, Ecto.Enum, values: @expense_profiles
    field :payment_method, Ecto.Enum, values: @payment_methods
    field :amount_cents, :integer
    field :category, :string
    field :description, :string
    field :occurred_on, :date

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def expense_profiles, do: @expense_profiles
  def payment_methods, do: @payment_methods

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :kind,
      :expense_profile,
      :payment_method,
      :amount_cents,
      :category,
      :description,
      :occurred_on
    ])
    |> validate_required([:kind, :amount_cents, :category, :occurred_on])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_length(:category, min: 2, max: 80)
    |> validate_length(:description, max: 300)
    |> validate_expense_classification()
    |> assoc_constraint(:user)
  end

  defp validate_expense_classification(changeset) do
    case get_field(changeset, :kind) do
      :expense -> validate_required(changeset, [:expense_profile, :payment_method])
      _ -> changeset
    end
  end
end
