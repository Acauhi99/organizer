defmodule Organizer.Repo.Migrations.RemoveTaskDomainTables do
  use Ecto.Migration

  def change do
    drop_if_exists table(:task_checklist_items)
    drop_if_exists table(:tasks)
  end
end
