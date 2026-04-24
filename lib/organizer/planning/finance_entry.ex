defmodule Organizer.Planning.FinanceEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Organizer.Accounts.User

  @kinds [:income, :expense]
  @expense_profiles [:fixed, :variable, :recurring_fixed, :recurring_variable]
  @payment_methods [:credit, :debit]
  @shared_split_modes [:income_ratio, :manual]
  @type kind :: :income | :expense
  @type expense_profile :: :fixed | :variable | :recurring_fixed | :recurring_variable
  @type payment_method :: :credit | :debit
  @type shared_split_mode :: :income_ratio | :manual

  @type t :: %__MODULE__{
          id: integer() | nil,
          kind: kind() | nil,
          expense_profile: expense_profile() | nil,
          payment_method: payment_method() | nil,
          installments_count: integer() | nil,
          amount_cents: integer() | nil,
          category: String.t() | nil,
          description: String.t() | nil,
          occurred_on: Date.t() | nil,
          shared_with_link_id: integer() | nil,
          shared_split_mode: shared_split_mode() | nil,
          shared_manual_mine_cents: integer() | nil,
          user_id: integer() | nil,
          user: term() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "finance_entries" do
    field :kind, Ecto.Enum, values: @kinds
    field :expense_profile, Ecto.Enum, values: @expense_profiles
    field :payment_method, Ecto.Enum, values: @payment_methods
    field :installments_count, :integer
    field :amount_cents, :integer
    field :category, :string
    field :description, :string
    field :occurred_on, :date
    field :shared_with_link_id, :integer
    field :shared_split_mode, Ecto.Enum, values: @shared_split_modes
    field :shared_manual_mine_cents, :integer

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def expense_profiles, do: @expense_profiles
  def payment_methods, do: @payment_methods
  def shared_split_modes, do: @shared_split_modes

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :kind,
      :payment_method,
      :installments_count,
      :amount_cents,
      :category,
      :description,
      :occurred_on,
      :shared_with_link_id,
      :shared_split_mode,
      :shared_manual_mine_cents
    ])
    |> cast_expense_profile(attrs)
    |> validate_required([:kind, :amount_cents, :category, :occurred_on])
    |> validate_number(:amount_cents, greater_than: 0, less_than_or_equal_to: 1_000_000_000)
    |> validate_number(:installments_count, greater_than: 0, less_than_or_equal_to: 120)
    |> validate_number(:shared_manual_mine_cents,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000_000
    )
    |> validate_length(:category, min: 2, max: 80)
    |> validate_length(:description, max: 300)
    |> validate_expense_classification()
    |> assoc_constraint(:user)
  end

  defp cast_expense_profile(changeset, attrs) do
    case get_field(changeset, :kind) do
      :income -> changeset
      _ -> cast(changeset, attrs, [:expense_profile])
    end
  end

  defp validate_expense_classification(changeset) do
    case get_field(changeset, :kind) do
      :expense ->
        changeset
        |> validate_required([:expense_profile, :payment_method])
        |> validate_installments_for_payment_method()

      _ ->
        put_change(changeset, :installments_count, nil)
    end
  end

  defp validate_installments_for_payment_method(changeset) do
    case get_field(changeset, :payment_method) do
      :credit ->
        validate_required(changeset, [:installments_count])

      _ ->
        put_change(changeset, :installments_count, nil)
    end
  end
end
