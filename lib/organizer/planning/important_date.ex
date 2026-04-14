defmodule Organizer.Planning.ImportantDate do
  use Ecto.Schema
  import Ecto.Changeset

  alias Organizer.Accounts.User

  @categories [:personal, :finance, :work]

  schema "important_dates" do
    field :title, :string
    field :category, Ecto.Enum, values: @categories, default: :personal
    field :date, :date
    field :notes, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(important_date, attrs) do
    important_date
    |> cast(attrs, [:title, :category, :date, :notes])
    |> validate_required([:title, :category, :date])
    |> validate_length(:title, min: 2, max: 100)
    |> validate_length(:notes, max: 300)
    |> assoc_constraint(:user)
  end
end
