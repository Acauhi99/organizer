defmodule Organizer.Repo.Migrations.CreateUserPreferences do
  use Ecto.Migration

  def change do
    create table(:user_preferences) do
      add :analytics_panel_default_visible, :boolean, default: true, null: false
      add :operations_panel_default_visible, :boolean, default: true, null: false
      add :onboarding_completed, :boolean, default: false, null: false
      add :preferred_layout_mode, :string, default: "expanded", null: false
      add :bulk_import_block_size_preference, :integer, default: 3, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_preferences, [:user_id])
  end
end
