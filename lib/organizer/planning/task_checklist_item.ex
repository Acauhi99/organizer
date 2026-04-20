defmodule Organizer.Planning.TaskChecklistItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Organizer.Planning.Task

  schema "task_checklist_items" do
    field :label, :string
    field :position, :integer, default: 0
    field :checked, :boolean, default: false
    field :checked_at, :utc_datetime

    belongs_to :task, Task

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:label, :position, :checked, :checked_at])
    |> validate_required([:label])
    |> update_change(:label, &String.trim/1)
    |> validate_length(:label, min: 1, max: 140)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> assoc_constraint(:task)
  end
end
