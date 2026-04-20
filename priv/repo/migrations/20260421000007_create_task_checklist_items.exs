defmodule Organizer.Repo.Migrations.CreateTaskChecklistItems do
  use Ecto.Migration

  def change do
    create table(:task_checklist_items) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :position, :integer, null: false, default: 0
      add :checked, :boolean, null: false, default: false
      add :checked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:task_checklist_items, [:task_id])
    create index(:task_checklist_items, [:task_id, :position])
    create index(:task_checklist_items, [:task_id, :checked])
  end
end
