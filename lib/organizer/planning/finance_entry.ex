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
          installment_number: integer() | nil,
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
    field :installment_number, :integer
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
      :expense_profile,
      :payment_method,
      :installment_number,
      :installments_count,
      :amount_cents,
      :category,
      :description,
      :occurred_on,
      :shared_with_link_id,
      :shared_split_mode,
      :shared_manual_mine_cents
    ])
    |> validate_required([:kind, :amount_cents, :category, :occurred_on])
    |> validate_number(:amount_cents, greater_than: 0, less_than_or_equal_to: 1_000_000_000)
    |> validate_number(:installment_number, greater_than: 0, less_than_or_equal_to: 120)
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

  defp validate_expense_classification(changeset) do
    case get_field(changeset, :kind) do
      :expense ->
        changeset
        |> validate_required([:expense_profile, :payment_method])
        |> validate_installments_for_payment_method()

      :income ->
        changeset
        |> ensure_income_profile()
        |> put_change(:payment_method, nil)
        |> put_change(:installments_count, nil)
        |> put_change(:installment_number, nil)

      _ ->
        put_change(changeset, :installments_count, nil)
        |> put_change(:installment_number, nil)
    end
  end

  defp ensure_income_profile(changeset) do
    case get_field(changeset, :expense_profile) do
      nil -> put_change(changeset, :expense_profile, :variable)
      _ -> changeset
    end
  end

  defp validate_installments_for_payment_method(changeset) do
    case get_field(changeset, :payment_method) do
      :credit ->
        changeset
        |> validate_required([:installments_count, :installment_number])
        |> validate_installment_number_bounds()

      _ ->
        changeset
        |> put_change(:installments_count, nil)
        |> put_change(:installment_number, nil)
    end
  end

  defp validate_installment_number_bounds(changeset) do
    installments_count = get_field(changeset, :installments_count)
    installment_number = get_field(changeset, :installment_number)

    if is_integer(installment_number) and is_integer(installments_count) and
         installment_number > installments_count do
      add_error(
        changeset,
        :installment_number,
        "must be less than or equal to installments_count"
      )
    else
      changeset
    end
  end
end
