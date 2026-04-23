defmodule Organizer.Repo.Migrations.AddTaskSharingFields do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :shared_with_link_id, references(:account_links, on_delete: :nilify_all)
      add :shared_pair_uuid, :string
      add :shared_origin_task_id, references(:tasks, on_delete: :nilify_all)
      add :shared_sync_mode, :string
    end

    create index(:tasks, [:shared_with_link_id])
    create index(:tasks, [:shared_pair_uuid])
    create index(:tasks, [:shared_origin_task_id])
  end
end
