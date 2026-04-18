defmodule Organizer.Planning.Goal do
  use Ecto.Schema
  import Ecto.Changeset

  alias Organizer.Accounts.User

  @horizons [:short, :medium, :long]
  @statuses [:active, :paused, :done]

  schema "goals" do
    field :title, :string
    field :horizon, Ecto.Enum, values: @horizons
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :target_value, :integer
    field :current_value, :integer, default: 0
    field :due_on, :date
    field :notes, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def horizons, do: @horizons
  def statuses, do: @statuses

  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:title, :horizon, :status, :target_value, :current_value, :due_on, :notes])
    |> validate_required([:title, :horizon, :status])
    |> validate_length(:title, min: 3, max: 140)
    |> validate_number(:current_value, greater_than_or_equal_to: 0)
    |> validate_number(:target_value, greater_than: 0)
    |> validate_length(:notes, max: 500)
    |> assoc_constraint(:user)
    |> validate_current_not_exceeds_target()
  end

  defp validate_current_not_exceeds_target(changeset) do
    current = get_field(changeset, :current_value)
    target = get_field(changeset, :target_value)

    if is_integer(current) and is_integer(target) and current > target do
      add_error(changeset, :current_value, "must be less than or equal to target_value")
    else
      changeset
    end
  end
end
