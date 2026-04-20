defmodule Organizer.Planning.Task do
  use Ecto.Schema
  import Ecto.Changeset

  alias Organizer.Accounts.User
  alias Organizer.Planning.TaskChecklistItem

  @statuses [:todo, :in_progress, :done]
  @priorities [:low, :medium, :high]

  schema "tasks" do
    field :title, :string
    field :notes, :string
    field :due_on, :date
    field :status, Ecto.Enum, values: @statuses, default: :todo
    field :priority, Ecto.Enum, values: @priorities, default: :medium
    field :completed_at, :utc_datetime

    belongs_to :user, User
    has_many :checklist_items, TaskChecklistItem, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def priorities, do: @priorities

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :notes, :due_on, :status, :priority, :completed_at])
    |> validate_required([:title, :status, :priority])
    |> validate_length(:title, min: 3, max: 120)
    |> validate_length(:notes, max: 1_000)
    |> assoc_constraint(:user)
  end
end
