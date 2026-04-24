defmodule Organizer.Repo.Migrations.RemoveGoalsAndBulkImportPreferences do
  use Ecto.Migration

  def up do
    drop_if_exists table(:goals)

    alter table(:user_preferences) do
      remove :bulk_import_block_size_preference, :integer, default: 3, null: false
    end
  end

  def down do
    alter table(:user_preferences) do
      add :bulk_import_block_size_preference, :integer, default: 3, null: false
    end

    create table(:goals) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :horizon, :string, null: false
      add :status, :string, null: false, default: "active"
      add :target_value, :integer
      add :current_value, :integer, default: 0, null: false
      add :due_on, :date
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:goals, [:user_id])
    create index(:goals, [:user_id, :horizon])
    create index(:goals, [:user_id, :status])
  end
end
