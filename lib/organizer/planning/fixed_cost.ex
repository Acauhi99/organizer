defmodule Organizer.Planning.FixedCost do
  use Ecto.Schema
  import Ecto.Changeset

  alias Organizer.Accounts.User

  @derive {
    Flop.Schema,
    filterable: [:name, :amount_cents, :billing_day, :active, :starts_on],
    sortable: [:billing_day, :name, :amount_cents, :inserted_at],
    default_order: %{
      order_by: [:billing_day, :name],
      order_directions: [:asc, :asc]
    },
    default_limit: 20,
    max_limit: 100
  }

  schema "fixed_costs" do
    field :name, :string
    field :amount_cents, :integer
    field :billing_day, :integer
    field :starts_on, :date
    field :active, :boolean, default: true

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(cost, attrs) do
    cost
    |> cast(attrs, [:name, :amount_cents, :billing_day, :starts_on, :active])
    |> validate_required([:name, :amount_cents, :billing_day])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_number(:amount_cents, greater_than: 0, less_than_or_equal_to: 1_000_000_000)
    |> validate_number(:billing_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> assoc_constraint(:user)
  end
end
